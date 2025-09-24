variable "project_name" { 
    type = string  
    default = "s3-zip-jobs" 
}

variable "aws_region"  { 
    type = string  
    default = "us-east-1" 
}

variable "src_bucket_name" { 
    type = string 
}

variable "dst_bucket_name" { 
    type = string 
}

variable "dst_prefix" { 
    type = string  
    default = "zips/" 
}

variable "presign_ttl_seconds" { 
    type = number 
    default = 86400 
}
