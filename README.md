# retool-docker-compose

A template to help you get run Retool Locally via Docker Desktop

## Prereqs

🐳 **Docker Desktop**: version 4.25+

In general settings:
- choose `VirtioFS` so that virtualization framework is enabled
- Enable `Use Rosetta for x86/amd64 emulation on Apple Silicon`

In resources:
- Allocate at least `4 CPU` and `8GB Memory`


🐙 [**Git**](https://git-scm.com/download/mac) installed, along with [**a SSH key configured**](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent) for your GitHub account in the [tryretool](https://github.com/tryretool) org.

💻 A **Text Editor/IDE** set up, and some comfort using a **Terminal** for CLI commands

## Getting Started

1) Use this template to create a new repo owned your github user, e.g `my-local-docker`

2) Clone that repo to your machine. If you don't already have one, create a folder in your home directory to help keep organized, e.g `~/local-retool`

3) Open up that repo in our text editor of choice

This template is made up of some [Dockerfiles](https://docs.docker.com/engine/reference/builder/#dockerfile-reference), some [Compose](https://docs.docker.com/compose/compose-file/03-compose-file/) files, and [dynamic configuration file](https://docs.temporal.io/references/dynamic-configuration) for Temporal (don't worry too much about this one).

There are two separate Compose files: one for a deployment with Workflows, and one without. I recommend working mostly with a non-Workflows deployment and spinning up the one with Workflows when needed.

## Initial Config

1) Set an image tag in the `Dockerfile` and optionally `CodeExecutor.Dockerfile` if you're spinning up Workflows with Python support

2) Rename the template env file to `docker.env`, and set the `JWT_SECRET` and `ENCRYPTION_KEY`. Optionally, you can replace the `LICENSE_KEY` with your own (which is useful for testing feature flags)

## Boot it up

Run the default `compose.yaml`:

```docker compose up -d --build```

Pass a specific compose file to use:

```docker compose -f compose-workflows.yaml up -d --build```

It typically takes around one minute for the deployment to be ready to handle requests, after which you can access it via `localhost:3000`.

To spin things down, run

```docker compose down```

## Get Aquainted with Docker Desktop

Spend some time getting familiar with the Docker Desktop UI, which will show the status of your services.

Primarily you'll use Docker Desktop to view container logs, see metrics/charts of your containers CPU and Memory, and `exec` into containers themselves.

### Docker Extensions

Third-party tools/apps to extend Docker Desktop functionality. I primarily use two:

[ContainerWatch](https://open.docker.com/extensions/marketplace?extensionId=containerwatch/containerwatch): Provides nice graphs for CPU and Memory usage for containers, and some nice logging.

[Docker Debug Tools](https://open.docker.com/extensions/marketplace?extensionId=docker/labs-debug-tools-extension): Makes `exec`ing into continers and running commands more pleasant

## Use a SQL GUI

One of the benefits running locally is being to easily inspect database state, and doing so is much easier using a GUI application (rather than running `psql` commands).

Install an app like [Postico](https://eggerapps.at/postico2/), [TablePlus](https://tableplus.com/), or something [from this list](https://postgresapp.com/documentation/gui-tools.html) to better view your deployment data, see table structure, and run ad-hoc queries.

## Set up a Cloud-hosted Postgres Database

This template starts with a `postgres` container that keeps your data in a local volume via Docker Desktop. If you ever lose this volume (e.g if you run `docker system prune`) then your data is gone.

Consider setting up a database on [Neon](https://neon.tech/), [Render](https://render.com/docs/databases), [Supabase](https://supabase.com/database), or another cloud service to manage your database for free or very cheap.

I personally pay for Neon (ends up $2 or so a month) primarily for their [Branching](https://neon.tech/docs/introduction/branching) feauture, which comes in very handy for testing Retool things across versions where database state can potentially get messed up.

### DB Migrations

New versions of Retool may include changes to the schema of the postgres database, and these are implemented through [DB Migrations](https://retoolconfluence.atlassian.net/wiki/spaces/FE/pages/162333218/Database+Migrations).

It's important to keep these in mind when doing large jumps between Retool versions locally using the same postgres volume/instance, as Retool does not run down-migrations automatically when you downgrade.

- DB Migration info is stored in the single-column `SequelizMeta` table (the beginning digits of each migration name roughly translate to the date it was first created)

- You can copy the name and search for it in Retool's codebase to find out what the migration is actually doing, and a link to the PR which should give more info on why it was created and what version it should be run in.

## Next steps

Power-up your local deployment by:

1) Creating a GitHub or GitLab repo to set up Source Control

2) Creating an Okta or Auth0 account to set up Custom SSO

3) Adding NGINX to your configuration to setup SSL
