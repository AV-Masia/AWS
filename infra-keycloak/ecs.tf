resource "aws_ecs_cluster" "keycloak" {
  name = "${var.project}-cluster"
}

resource "aws_cloudwatch_log_group" "keycloak" {
  name              = "/ecs/${var.project}"
  retention_in_days = 7
}

resource "aws_lb" "keycloak" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnet_ids
}

resource "aws_lb_target_group" "keycloak" {
  name        = "${var.project}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/health/ready"
    port                = "9000"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 15
    timeout             = 10
  }
}

resource "aws_lb_listener" "keycloak" {
  load_balancer_arn = aws_lb.keycloak.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.keycloak.arn
  }
}

# --- IAM ------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.project}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Execution role читает секрет при старте задачи (admin password). Креды
# Aurora больше не читаются задачей — аутентификация только через IAM
# (см. task_rds_iam_auth ниже), aurora_db secret оставлен как справочный.
data "aws_iam_policy_document" "execution_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.keycloak_admin.arn,
    ]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "${var.project}-execution-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

resource "aws_iam_role" "task" {
  name               = "${var.project}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "task_exec" {
  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_exec" {
  name   = "${var.project}-task-exec"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_exec.json
}

data "aws_caller_identity" "current" {}

# Aurora принимает только IAM DB auth (см. aurora.tf) — AWS JDBC Wrapper
# в образе Keycloak генерирует токен через эту роль при каждом новом
# соединении в пуле, вместо статического пароля.
data "aws_iam_policy_document" "task_rds_iam_auth" {
  statement {
    actions = ["rds-db:connect"]
    resources = [
      "arn:aws:rds-db:${var.region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.keycloak.cluster_resource_id}/${var.db_username}",
    ]
  }
}

resource "aws_iam_role_policy" "task_rds_iam_auth" {
  name   = "${var.project}-task-rds-iam-auth"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_rds_iam_auth.json
}

# --- Task definition --------------------------------------------------------------

resource "aws_ecs_task_definition" "keycloak" {
  family                   = "${var.project}-keycloak"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name  = "keycloak"
      image = "${aws_ecr_repository.keycloak.repository_url}:${var.keycloak_image_tag}"
      # health-эндпоинт (9000) и приложение (8080) публикуем оба, ALB следит за 9000
      portMappings = [
        { containerPort = 8080, protocol = "tcp" },
        { containerPort = 9000, protocol = "tcp" },
      ]
      essential = true
      # образ уже собран через kc.sh build (docker/Dockerfile) — --optimized
      # пропускает повторную аугментацию при каждом старте
      command = ["start", "--optimized", "--hostname-strict=false"]
      environment = [
        { name = "AWS_REGION", value = var.region },
        { name = "KC_DB", value = "postgres" },
        # aws-wrapper: JDBC-обёртка генерирует IAM auth token при каждом новом
        # соединении в пуле вместо статического пароля (см. aurora.tf и
        # ecs.tf/task_rds_iam_auth — Aurora здесь принимает только IAM auth).
        { name = "KC_DB_URL", value = "jdbc:aws-wrapper:postgresql://${aws_rds_cluster.keycloak.endpoint}:${aws_rds_cluster.keycloak.port}/${var.db_name}?wrapperPlugins=iam" },
        { name = "KC_DB_USERNAME", value = var.db_username },
        # Значение не используется для аутентификации (IAM-плагин его игнорирует
        # и подставляет токен), но Agroal требует непустую строку в конфиге.
        { name = "KC_DB_PASSWORD", value = "unused-iam-overrides-this" },
        { name = "KC_HTTP_ENABLED", value = "true" },
        { name = "KC_PROXY_HEADERS", value = "xforwarded" },
        { name = "REDIS_HOST", value = aws_elasticache_cluster.keycloak.cache_nodes[0].address },
        { name = "REDIS_PORT", value = tostring(aws_elasticache_cluster.keycloak.cache_nodes[0].port) },
      ]
      secrets = [
        { name = "KEYCLOAK_ADMIN", valueFrom = "${aws_secretsmanager_secret.keycloak_admin.arn}:username::" },
        { name = "KEYCLOAK_ADMIN_PASSWORD", valueFrom = "${aws_secretsmanager_secret.keycloak_admin.arn}:password::" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.keycloak.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "keycloak"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "keycloak" {
  name            = "${var.project}-keycloak"
  cluster         = aws_ecs_cluster.keycloak.id
  task_definition = aws_ecs_task_definition.keycloak.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Нужен, чтобы зайти в контейнер (aws ecs execute-command) и один раз
  # отключить sslRequired у master realm — HTTP-демо без своего домена/ACM.
  enable_execute_command = true

  # Первый старт: Liquibase накатывает 148 changeset'ов через интернет до
  # Aurora (~330с на практике). Без grace period ECS убьёт таску раньше,
  # чем миграция закончится. Последующие рестарты будут заметно быстрее —
  # схема уже накачена.
  health_check_grace_period_seconds = 600

  network_configuration {
    subnets          = local.subnet_ids
    security_groups  = [aws_security_group.keycloak.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.keycloak.arn
    container_name    = "keycloak"
    container_port    = 8080
  }

  depends_on = [aws_lb_listener.keycloak]
}
