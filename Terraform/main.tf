# main.tf
module "frontend" {
  source = "./Frontend"
  
}

module "backend" {
  source = "./Backend"
  
}
