output "alb_dns_name" {
  value = aws_lb.ecs_lb.dns_name
}
output "nginx_php_image_uri" {
  value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/nginx-php:latest"
}
output "mysql_image_uri" {
  value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/mysql:latest"
}