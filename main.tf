resource "aws_instance" "main" {
  ami                    = local.ami_id
  instance_type          = "t3.micro"
  subnet_id              = local.private_subnet_id
  vpc_security_group_ids = [local.sg_id]

  tags = merge(
    local.common_tags,
    {
      Name = "${var.Project}-${var.Environment}-${var.component}"
  })
}

resource "terraform_data" "bootstrap" {
  triggers_replace = [
    aws_instance.main.id
  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    password = "DevOps321"
    host     = aws_instance.main.private_ip
  }
  provisioner "file" {
    source      = "bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sleep 60",
      "chmod +x /tmp/bootstrap.sh",
      "sudo sh /tmp/bootstrap.sh ${var.component} ${var.Environment} ${var.app_version}",
    ]
  }

}


resource "aws_ec2_instance_state" "main" {
  instance_id = aws_instance.main.id
  state       = "stopped"
  depends_on  = [terraform_data.bootstrap]
}

resource "aws_ami_from_instance" "main" {
  name               = "${var.Project}-${var.Environment}-${var.component}-${var.app_version}-${aws_instance.main.id}"
  source_instance_id = aws_instance.main.id
  depends_on         = [aws_ec2_instance_state.main]
}


resource "aws_lb_target_group" "main" {

  name                 = "${var.Project}-${var.Environment}-${var.component}"
  port                 = local.port_number
  protocol             = "HTTP"
  vpc_id               = local.vpc_id
  deregistration_delay = 60
  health_check {
    enabled             = true
    path                = local.health_check_path
    port                = local.port_number
    protocol            = "HTTP"
    timeout             = 2
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200-299"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.Project}-${var.Environment}-${var.component}"
  })
}

resource "aws_launch_template" "main" {
  name                                 = "${var.Project}-${var.Environment}-${var.component}"
  image_id                             = aws_ami_from_instance.main.id
  instance_initiated_shutdown_behavior = "terminate"
  instance_type                        = "t3.micro"
  vpc_security_group_ids               = [local.sg_id]

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      local.common_tags,
      {
        Name = "${var.Project}-${var.Environment}-${var.component}"
    })
  }
  tag_specifications {
    resource_type = "volume"

    tags = merge(
      local.common_tags,
      {
        Name = "${var.Project}-${var.Environment}-${var.component}"
    })
  }
  tags = merge(
    local.common_tags,
    {
      Name = "${var.Project}-${var.Environment}-${var.component}"
  })

}


resource "aws_autoscaling_group" "main" {
  name                      = "${var.Project}-${var.Environment}-${var.component}"
  max_size                  = 10
  min_size                  = 1
  health_check_grace_period = 120
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete              = false

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  vpc_zone_identifier = [local.private_subnet_id]
  target_group_arns   = [aws_lb_target_group.main.arn]

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]
  }

  dynamic "tag" {
    for_each = merge(
      local.common_tags,
      {
        Name = "${var.Project}-${var.Environment}-${var.component}"
    })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  timeouts {
    delete = "15m"
  }
}

resource "aws_autoscaling_policy" "main" {
  autoscaling_group_name = aws_autoscaling_group.main.name
  name                   = "${var.Project}-${var.Environment}-${var.component}"
  policy_type            = "TargetTrackingScaling"
  estimated_instance_warmup = 120


  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }

}

resource "aws_lb_listener_rule" "main" {
  listener_arn = local.alb_listener_arn

  priority     = var.rule_priority
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
  condition {
    host_header {
      values = []

    }
  }
}

resource "terraform_data" "main_delete" {
  triggers_replace = [
    aws_instance.main.id
  ]
  
  depends_on = [ aws_autoscaling_policy.main,
                 aws_ami_from_instance.main ]
  provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${aws_instance.main.id}"
  }
}
