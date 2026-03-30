
resource "aws_ecr_repository" "ecr_repo" {
  name = "nodejs-app"
  image_scanning_configuration {
    scan_on_push = true
  }
}
# create ecr repo on aws with name nodejs-app
#  ecr_repo is name of rg 
# image_scanning_configuration : enable image scanning on push to identify vulnerabilities in container images.