provider "aws" {
  region  = "ap-south-1"
  profile = "shubham"
}

#Security-Group
resource "aws_security_group" "task2-sg" {
  name        = "task2_sg"
  description = "allows HTTP, SSH, and NFS"

  ingress {
    description = "for HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "for SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "for NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task2_sg"
  }
}

#EFS
resource "aws_efs_file_system" "webefs" {
  creation_token = "myefs"

  tags = {
    Name = "myefs"
  }

  depends_on = [
    aws_security_group.task2-sg,
  ]
}

#Mounting_EFS_To_A_Subnet
resource "aws_efs_mount_target" "web_mount" {
  file_system_id = aws_efs_file_system.webefs.id
  subnet_id      = "subnet-4af09a06"
  security_groups = [aws_security_group.task2-sg.id]

    depends_on = [
    aws_efs_file_system.webefs,
  ]
}

#Creating_Key_Pair
resource "tls_private_key" "key123" {
  algorithm = "RSA"
}

resource "aws_key_pair" "task2-key" {
  key_name = "task2-key"
  public_key = tls_private_key.key123.public_key_openssh
}

#Instance
resource "aws_instance" "myweb" {
  ami           = "ami-052c08d70def0ac62"
  instance_type = "t2.micro"
  key_name = "task2-key"
  subnet_id      = "subnet-4af09a06"
  security_groups = [aws_security_group.task2-sg.id]
  
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.key123.private_key_pem
    host     = aws_instance.myweb.public_ip
 }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd -y",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
      "sudo yum install nfs-utils -y",
      "sudo yum install amazon-efs-utils -y",
      "sudo yum install git -y",
      "sudo mount -t efs ${aws_efs_file_system.webefs.id}:/ /var/www/html",
      "sudo echo ${aws_efs_file_system.webefs.id}:/ /var/www/html efs defaults,_netdev 0 0 >> sudo /etc/fstab",
      "sudo rm -f /var/www/html/*",
      "sudo git clone https://github.com/devilsm13/Terraform_task2 /var/www/html/",
    ]
  }
      
  tags = {
    Name = "myweb"
  }

    depends_on = [
    aws_efs_mount_target.web_mount,
  ]
}

#S3_Bucket
resource "aws_s3_bucket" "web-bucket" {
  bucket = "task2-bucket"
  acl    = "public-read"

  tags = {
    Name        = "task2-bucket"
  }
}

#Uploading_Image_To_Bucket
resource "aws_s3_bucket_object" "task2-img" {
  bucket = aws_s3_bucket.web-bucket.bucket
  key = "myimg"
  content_type = "image/jpg"
  source = "C:/Users/sm810/Desktop/myimg.jpeg"
  acl = "public-read"

    depends_on = [
    aws_s3_bucket.web-bucket,
  ]
}

#OAI
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "web_cf"

    depends_on = [
    aws_s3_bucket_object.task2-img,
  ]
}

locals {
 s3_origin_id = "aws_s3_bucket.task2-bucket.id"
}

#Cloudfront_Distribution
resource "aws_cloudfront_distribution" "task2-cf" {
  enabled = true
  is_ipv6_enabled = true

  origin {
    domain_name = aws_s3_bucket.web-bucket.bucket_domain_name
    origin_id = local.s3_origin_id
  }

  default_cache_behavior {
    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl = 0
    default_ttl = 3600
    max_ttl = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [
    aws_cloudfront_origin_access_identity.oai,
  ]

}

#Updating_HTML_Code
resource "null_resource" "mynull" {
 connection {
  type     = "ssh"
  user     = "ec2-user"
  private_key = tls_private_key.key123.private_key_pem
  host     = aws_instance.myweb.public_ip
 }

 provisioner "remote-exec" {
  inline = [
   "sudo su << EOF",
   "echo \"<img src='http://${aws_cloudfront_distribution.task2-cf.domain_name}/${aws_s3_bucket_object.task2-img.key}' height='200' width = '200'>\" >> /var/www/html/index.html",
   "EOF",
   "sudo systemctl restart httpd",
  ]
 }
  depends_on = [ 
   aws_cloudfront_distribution.task2-cf,
   aws_instance.myweb,
  ]
}

#Instance_IP
output "Instance_IP" {
  value = aws_instance.myweb.public_ip
}
