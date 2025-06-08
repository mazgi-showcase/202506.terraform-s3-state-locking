terraform {
  backend "s3" {
    key          = "default/terraform"
    use_lockfile = true
  }
}
