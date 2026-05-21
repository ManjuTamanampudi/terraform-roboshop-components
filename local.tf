locals {
  ami_id= data.aws_ami.joindevops.id
   private_subnet_id= split(",",data.aws_ssm_parameter.private_subnet_id.value)[0]
   sg_id = data.aws_ssm_parameter.sg_id.value
   vpc_id = data.aws_ssm_parameter.vpc_id.value
   health_check_path = var.component == "frontend" ? "/" : "/health"
   port_number = var.component == "frontend" ? 80 : 8080
  backend_alb_listener_arn =data.aws_ssm_parameter.backend_alb_listener_arn.value
  frontend_alb_listener_arn =data.aws_ssm_parameter.frontend_alb_listener_arn.value
  alb_listener_arn = var.component == "frontend" ? local.frontend_alb_listener_arn : local.backend_alb_listener_arn
  host_header = var.component == "frontend" ? "${var.component}-${var.Environment}.${var.domain_name}" : "${var.component}.backend-alb-${var.Environment}.${var.domain_name}"
  common_tags={
    Project= var.Project
    Environment =var.Environment
    Terraform = true
  }
  }