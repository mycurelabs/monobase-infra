backup_project_id    = "mycure-dr-backup"
source_project_id    = "mc-v4-prod"
source_bucket        = "mc-v4-prod.appspot.com"
backup_bucket        = "mycure-prod-appspot-dr" # globally unique — change if taken
backup_location      = "us-central1"
backup_storage_class = "NEARLINE"
retention_days       = 30
schedule_start_date  = { year = 2026, month = 9, day = 5 }
tf_operators         = ["user:tubig.jlu@gmail.com"]
