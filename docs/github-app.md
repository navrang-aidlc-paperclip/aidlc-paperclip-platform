# GitHub App for the conductor

The conductor never holds a personal token. It mints a short-lived
installation token from a GitHub App (`conductor/bin/git-credential-github-app`)
every time `git` talks to github.com.

## Create the app

Org settings → Developer settings → GitHub Apps → **New GitHub App**

| Field | Value |
| --- | --- |
| Name | `aidlc-conductor` |
| Homepage URL | your Paperclip URL |
| Webhook | **inactive** (Paperclip polls; no inbound webhooks in the pilot) |
| Where can it be installed | Only this account |

Repository permissions:

| Permission | Level | Why |
| --- | --- | --- |
| Contents | Read & write | clone, push record commits, push `aidlc/<record>/<unit>` branches |
| Pull requests | Read & write | open PRs in source repos |
| Metadata | Read | required |
| Issues | Read | link issues (optional) |
| Workflows | Read & write | only if generated code includes GitHub Actions files |

Organization permissions: none.

## Install and collect ids

1. **Install App** on org `navrang-aidlc-paperclip`. Grant each project
   repository as it is added to the board. The image does not name any of them.
2. Note the **App ID** (app settings page) and the **Installation ID** (the
   number at the end of the URL after installing:
   `.../settings/installations/<id>`).
3. **Generate a private key**; save the `.pem` under
   `cloudformation/secrets/` (gitignored) and reference it from `deploy.env`
   as `GITHUB_APP_PRIVATE_KEY_FILE`.

## Branch protection

On each project repository, protect the default branch: require a pull
request and CODEOWNERS review, and do **not** add the app to the bypass
list. The conductor opens PRs; humans merge.
