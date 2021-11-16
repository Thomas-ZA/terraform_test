//aws ec2

variable "instancesize" {
  type = string
  default = "t3.micro"
}

variable "blocksize" {
  type = string
  default = "10"
}


//aws rds
variable "dbname" {
  type = string
  default = "dbname123"
}

variable "dbuser" {
  type = string
  default = "dbrootuser"
}

variable "dbspace" {
  type = string
  default = "20" 
}

variable "dbsize" {
  type = string
  default = "db.t3.micro"
}

variable "dbpass" {
  type = string
  default = "DbPass1234"
//  sensitive = true
}


