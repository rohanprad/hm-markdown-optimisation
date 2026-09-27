"""One-off load of the H&M Kaggle export into BigQuery.

After this runs, all analysis happens in BigQuery SQL (see ../sql).

Tables created in dataset `hm`:
  - articles      product master (one row per article)
  - transactions  one row per item sold, clustered by date and article_id so
                  queries only scan the dates/products they need

Note: clustered, not partitioned. The BigQuery sandbox deletes date partitions
older than 60 days, which would silently drop all of this 2018-2020 data.

Usage:
    python load/load_to_bigquery.py <project-id> "<folder with the extracted CSVs>"
"""
import sys
import warnings
from pathlib import Path

import pydata_google_auth
from google.cloud import bigquery

warnings.filterwarnings("ignore", message="BigQuery Storage module not found")

DATASET = "hm"
LOCATION = "EU"

# Explicit schemas: article_id must stay a STRING or its leading zero is lost
SCHEMAS = {
    "articles": [
        bigquery.SchemaField("article_id", "STRING"),
        bigquery.SchemaField("product_code", "STRING"),
        bigquery.SchemaField("prod_name", "STRING"),
        bigquery.SchemaField("product_type_no", "INT64"),
        bigquery.SchemaField("product_type_name", "STRING"),
        bigquery.SchemaField("product_group_name", "STRING"),
        bigquery.SchemaField("graphical_appearance_no", "INT64"),
        bigquery.SchemaField("graphical_appearance_name", "STRING"),
        bigquery.SchemaField("colour_group_code", "STRING"),
        bigquery.SchemaField("colour_group_name", "STRING"),
        bigquery.SchemaField("perceived_colour_value_id", "INT64"),
        bigquery.SchemaField("perceived_colour_value_name", "STRING"),
        bigquery.SchemaField("perceived_colour_master_id", "INT64"),
        bigquery.SchemaField("perceived_colour_master_name", "STRING"),
        bigquery.SchemaField("department_no", "INT64"),
        bigquery.SchemaField("department_name", "STRING"),
        bigquery.SchemaField("index_code", "STRING"),
        bigquery.SchemaField("index_name", "STRING"),
        bigquery.SchemaField("index_group_no", "INT64"),
        bigquery.SchemaField("index_group_name", "STRING"),
        bigquery.SchemaField("section_no", "INT64"),
        bigquery.SchemaField("section_name", "STRING"),
        bigquery.SchemaField("garment_group_no", "INT64"),
        bigquery.SchemaField("garment_group_name", "STRING"),
        bigquery.SchemaField("detail_desc", "STRING"),
    ],
    "transactions": [
        bigquery.SchemaField("t_dat", "DATE"),
        bigquery.SchemaField("customer_id", "STRING"),
        bigquery.SchemaField("article_id", "STRING"),
        bigquery.SchemaField("price", "FLOAT64"),
        bigquery.SchemaField("sales_channel_id", "INT64"),
    ],
}
FILES = {"articles": "articles.csv", "transactions": "transactions_train.csv"}


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    project_id, folder = sys.argv[1], Path(sys.argv[2])

    creds = pydata_google_auth.get_user_credentials(
        ["https://www.googleapis.com/auth/bigquery"], use_local_webserver=True
    )
    bq = bigquery.Client(project=project_id, credentials=creds, location=LOCATION)
    bq.create_dataset(bigquery.Dataset(f"{project_id}.{DATASET}"), exists_ok=True)

    for table, filename in FILES.items():
        config = bigquery.LoadJobConfig(
            schema=SCHEMAS[table],
            source_format=bigquery.SourceFormat.CSV,
            skip_leading_rows=1,
            allow_quoted_newlines=True,  # some product descriptions contain line breaks
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        )
        table_id = f"{project_id}.{DATASET}.{table}"
        if table == "transactions":
            config.clustering_fields = ["t_dat", "article_id"]
            # WRITE_TRUNCATE can't change a table's partitioning, so start fresh
            bq.delete_table(table_id, not_found_ok=True)

        print(f"Uploading {filename} -> {table_id} ...", flush=True)
        with open(folder / filename, "rb") as f:
            job = bq.load_table_from_file(f, table_id, job_config=config)
        job.result()
        print(f"  loaded {bq.get_table(table_id).num_rows:,} rows", flush=True)


if __name__ == "__main__":
    main()
