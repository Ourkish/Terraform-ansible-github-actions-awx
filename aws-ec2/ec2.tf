provider "aws" {
  region     = "us-east-1"
  access_key = "PUT YOUR OWN"
  secret_key = "PUT YOUR OWN"
}

terraform {
  backend "s3" {
    bucket     = "terraform-backend-ourkish123"
    key        = "ourkish.tfstate"
    region     = "us-east-1"
    access_key = "PUT YOUR OWN"
    secret_key = "PUT YOUR OWN"
  }
}

# Create a new VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "ourkish-vpc"
  }
}

# Create a new Subnet
resource "aws_subnet" "my_subnet" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

# Create an Internet Gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "ourkish-igw"
  }
}

# Create a Route Table
resource "aws_route_table" "my_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }
}

# Associate the route table with the subnet
resource "aws_route_table_association" "my_route_table_assoc" {
  subnet_id      = aws_subnet.my_subnet.id
  route_table_id = aws_route_table.my_route_table.id
}

# Fetch the latest Ubuntu AMI
data "aws_ami" "ubuntu_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  owners = ["099720109477"]
}

# Create an EC2 Instance
resource "aws_instance" "myec2" {
  ami                    = data.aws_ami.ubuntu_ami.id
  instance_type          = var.instancetype
  key_name               = "devops-ourkish"
  tags                   = var.aws_common_tag
  vpc_security_group_ids = [aws_security_group.allow_ssh_http_https.id]
  subnet_id              = aws_subnet.my_subnet.id

  root_block_device {
    delete_on_termination = true
  }

  depends_on = [aws_security_group.allow_ssh_http_https]
}

# Null resource for provisioning after instance is ready
resource "null_resource" "provisioner" {
  provisioner "remote-exec" {
    inline = [
      "sudo apt update -y",
      "sudo apt install -y nginx",
      "sudo systemctl start nginx",
      "sleep 30",  # Wait for 30 seconds before starting the provisioning steps
      
      # Install Docker non-interactively
      "sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      "sudo add-apt-repository -y \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\"",
      "sudo apt-get update -y",
      "sudo apt-get install -y docker-ce",
      
      # Start Docker and enable it to run on startup
      "sudo systemctl start docker",
      "sudo systemctl enable docker",

      # Install Docker Compose
      "sudo curl -L \"https://github.com/docker/compose/releases/download/$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '\"tag_name\": \"\\K.*?(?=\")')/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose",
      "sudo chmod +x /usr/local/bin/docker-compose",

      # Install Git
      "sudo apt-get install -y git",

      # Verify installation
      "docker --version",
      "docker-compose --version",
      "git --version",

      "cd /home/ubuntu/",
      "git clone https://github.com/diranetafen/diveintoansible-lab.git"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("./devops-ourkish.pem")
      host        = aws_instance.myec2.public_ip  # Use the instance's public IP
    }
  }

  depends_on = [aws_instance.myec2]
}

# Create a security group for the instance
resource "aws_security_group" "allow_ssh_http_https" {
  name        = "ourkish-sg"
  description = "Allow HTTP, HTTPS, and SSH inbound traffic"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from VPC"
    from_port   = 81
    to_port     = 81
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from VPC"
    from_port   = 1000
    to_port     = 1000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create an Elastic IP, but don't assign it until after the instance is created
resource "aws_eip" "lb" {
  vpc      = true
}

# Associate the Elastic IP with the EC2 instance
resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.myec2.id
  allocation_id = aws_eip.lb.id
}

# Output the public IP of the Elastic IP after association
output "eip_public_ip" {
  value = aws_eip.lb.public_ip
}
