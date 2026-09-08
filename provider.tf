provider "aws" {
  profile = "default"
  region  = "eu-west-3"

  default_tags {
    tags = {
      Project   = "bankapp"
      ManagedBy = "terraform"
      Team      = "us-team"
    }
  }
}