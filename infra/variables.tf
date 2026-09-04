variable "region" {
  description = "Регион AWS. Задание 1 сделано в eu-central-1, остаёмся там же"
  type        = string
  default     = "eu-central-1"
}

variable "project" {
  description = "Префикс имён и тег для всех ресурсов демо"
  type        = string
  default     = "legacy-migration"
}

variable "my_ip" {
  description = <<-EOT
    Внешний IP машины, с которой сеем legacy-БД. Только он получает доступ к порту 5432.
    Узнать: curl -s https://checkip.amazonaws.com
  EOT
  type        = string
}

variable "db_name" {
  description = "Имя базы внутри инстанса RDS"
  type        = string
  default     = "legacy"
}

variable "db_username" {
  description = "Мастер-пользователь RDS. postgres/admin/root — зарезервированы или напрашиваются на брутфорс"
  type        = string
  default     = "legacy_admin"
}

variable "secret_name" {
  description = "Имя секрета в Secrets Manager с кредами legacy-БД"
  type        = string
  default     = "legacy-db/postgres"
}
