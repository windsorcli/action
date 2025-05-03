terraform {
  required_version = ">= 1.0.0"
}

resource "local_file" "test" {
  content  = var.message
  filename = "test.txt"
} 
