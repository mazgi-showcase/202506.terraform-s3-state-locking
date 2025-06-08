terraform {
  # https://www.terraform.io/downloads.html
  # See https://www.terraform.io/language/expressions/version-constraints#version-constraint-syntax
  #  = (or no operator): Allows only one exact version number. Cannot be combined with other conditions.
  #  !=: Excludes an exact version number.
  #  >, >=, <, <=: Comparisons against a specified version, allowing versions for which the comparison is true. "Greater-than" requests newer versions, and "less-than" requests older versions.
  #  ~>: Allows only the rightmost version component to increment. For example, to allow new patch releases within a specific minor release, use the full version number: ~> 1.0.4 will allow installation of 1.0.5 and 1.0.10 but not 1.1.0. This is usually called the pessimistic constraint operator.
  required_version = "~> 1.11.0"
}
