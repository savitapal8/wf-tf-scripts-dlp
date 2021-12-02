provider "google" {
}

# DLP Inspect SA
resource "google_service_account" "dlp_inspect_sa" {
 account_id   = "dlp-inspect-sa"
 display_name = "DLP Inspect Service Account"
 project      = data.google_project.project.project_id
}


# Allow the custom inspect SA to be able to use jobs and templates to inspect data
resource "google_project_iam_member" "dlp_inspect" {
 project = data.google_project.project.id
 role    = "roles/dlp.user"
 member  = "serviceAccount:${google_service_account.dlp_inspect_sa.email}"
}

# Get project information
data "google_project" "project" {
    project_id = "airline1-sabre-wolverine"
}

# Grant DLP Service Agent access to CMEK KMS Key
resource "google_kms_crypto_key_iam_member" "target_resource_encryption1" {
 crypto_key_id = "projects/airline1-sabre-wolverine/locations/us/keyRings/savita-keyring-us/cryptoKeys/savita-key-us"
 role   = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
 member = "serviceAccount:service-${data.google_project.project.number}@dlp-api.iam.gserviceaccount.com"
}

# Grant Custom Inspect SA access to the CMEK KMS Key
resource "google_kms_crypto_key_iam_member" "target_resource_encryption" {
 crypto_key_id = "projects/airline1-sabre-wolverine/locations/us/keyRings/savita-keyring-us/cryptoKeys/savita-key-us"
 role   = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
 member = "serviceAccount:${google_service_account.dlp_inspect_sa.email}"
}


resource "google_data_loss_prevention_inspect_template" "inspect_example" {
 parent       = "projects/airline1-sabre-wolverine/locations/us-central1"

 inspect_config {
   #Rule to increase likelihood to custom ID if found 30 characters from CID keyword.
    info_types {
        name = "EMAIL_ADDRESS"
    }
   rule_set {
      info_types {
                name = "EMAIL_ADDRESS"
            }
            rules {
                exclusion_rule {
                    regex {
                        pattern = ".+@example.com"
                    }
                    matching_type = "MATCHING_TYPE_FULL_MATCH"
                }
            }
   }
 }
}


# Create the BigQuery dataset resource to store DLP scan outputs 
resource "google_bigquery_dataset" "dlp" {
  dataset_id   = "demo_bqdataset"  
  project      = "airline1-sabre-wolverine"
}

# Grant data access to a group of users
/*
resource "google_bigquery_dataset_iam_member" "editor" {
  dataset_id = google_bigquery_dataset.dlp.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "group:<group_id>@wellsfargo.com"
}
*/

resource "google_data_loss_prevention_job_trigger" "bq_job_example" {
  parent       = "projects/airline1-sabre-wolverine/locations/us-central1"
  description  = "Weekly scan on BQ table"
  display_name = "demo-dlpjob"

  triggers {
    schedule {
      recurrence_period_duration = "604800s"
    }
  }

  inspect_job {
    inspect_template_name = google_data_loss_prevention_inspect_template.inspect_example.id
    actions {
      save_findings {
        output_config {
          table {
            project_id = "airline1-sabre-wolverine"
            dataset_id = google_bigquery_dataset.dlp.id
            #table_id   = "<dlp_findings_table_name>"
          }
        }
      }    
       
       }

      storage_config {
          cloud_storage_options {
              file_set {
                  url = "gs://my_bucket_df/"
              }
          }
      }
    }
}
