# edit30terraform

Terraform for the Azure infrastructure behind edit30:

| Resource | Terraform | Used for |
| --- | --- | --- |
| Static Web App | `azurerm_static_web_app.frontend` | `edit30app` (React / CRA) |
| App Service (Linux, Node 20) + plan | `azurerm_linux_web_app.backend`, `azurerm_service_plan.backend` | `edit30backend` (Fastify) |
| SQL server + database (serverless, **free offer**) | `azurerm_mssql_server.main`, `azapi_resource.sql_database` | `edit30backend` data |
| Storage account + private `uploads` container | `azurerm_storage_account.main`, `azurerm_storage_container.main` | blob storage, e.g. uploaded images |
| Resource group | `azurerm_resource_group.main` | holds everything |

The App Service gets `SQL_CONNECTION_STRING` (server, database and a generated admin password) and
`CORS_ORIGIN` (the Static Web App's URL) automatically. Other settings mirror the old
`edit30backend/azure/main.bicep`: B1 plan, `npm run start`, `PORT=8080`, build on deploy.

## The free SQL database

The database uses Azure SQL's [free offer](https://learn.microsoft.com/azure/azure-sql/database/free-offer):
General Purpose serverless with **100,000 vCore-seconds and 32 GB of storage per month**, at no charge.

- **One free database per subscription.** If the subscription already has one, `apply` fails.
- `sql_free_limit_exhaustion_behavior = "AutoPause"` (default) pauses the database when the monthly
  vCore-seconds run out, so it can never bill you; it comes back at the start of next month.
  `"BillOverUsage"` keeps it running and bills the overage instead.
- It also **auto-pauses after 60 idle minutes**. The first request after that waits while it resumes
  (up to about a minute); the backend retries connections during that time.
- Not every region offers it. If `apply` complains about the free offer or about the region not accepting
  new SQL servers, set `location` to another region (e.g. `northeurope`, `swedencentral`).
- The `azurerm` provider can't set the free-offer flags yet, so the database is created with the
  `azapi` provider. Nothing else about it is unusual.
- Firewall: Azure services (incl. the App Service) are allowed. To connect from your own machine, add your
  IP to `sql_client_ip_addresses`.

## Usage

```bash
az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

terraform init
terraform plan
terraform apply
```

Or copy `terraform.tfvars.example` to `terraform.tfvars` and edit it. No secrets need to be supplied: the SQL
admin password is generated and kept in Terraform state.

## Deploying the apps

**Backend**

```bash
cd ../edit30backend
az webapp up --resource-group "$(terraform -chdir=../edit30terraform output -raw resource_group_name)" \
  --name "$(terraform -chdir=../edit30terraform output -raw backend_app_name)" \
  --runtime "NODE:20-lts"
```

On first start the backend creates its tables and seeds the starting cast.

**Frontend** — `REACT_APP_API_URL` is baked in at build time, so build with the backend URL, then deploy:

```bash
cd ../edit30app
REACT_APP_API_URL="$(terraform -chdir=../edit30terraform output -raw frontend_api_url)" npm run build
npx @azure/static-web-apps-cli deploy ./build \
  --deployment-token "$(terraform -chdir=../edit30terraform output -raw static_web_app_deployment_token)"
```

Since edit30app is a single-page app with `react-router`, add a `staticwebapp.config.json` with a
`navigationFallback` to `/index.html` (e.g. in `edit30app/public/`) so deep links don't 404.

## Notes

- **State is local** and contains secrets (SQL admin password, deployment token, connection strings). It is
  git-ignored; for shared use, move it to an `azurerm` remote backend.
- Web app, SQL server and storage account names get a random 4-character suffix because they must be globally unique.
- `terraform output -raw sql_connection_string` / `static_web_app_deployment_token` / `storage_connection_string`
  reveal sensitive outputs.
- App Service cost: the B1 plan is the only thing here that isn't free. Set `app_service_sku = "F1"` for a free plan
  (no Always On, daily CPU quota).
