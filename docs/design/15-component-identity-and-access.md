# Component Design: Identity and Access

Oct 9, 2026 · @Dodoe

Identity and access covers every identity in the tool and the least rights each one needs. Part of Doc.

## Principles

RDG has no stored passwords or client secrets anywhere, and every identity holds only what its own job needs.

- **No secrets:** managed identities for runtime, workload identity federation for the pipeline, a Key Vault certificate for web sign-in.
- **One writer per thing:** only "engine" changes groups; only "api" changes configuration; the pipeline changes Azure resources but no data and no tenant permissions.
- **No directory admin roles:** no identity holds Global, Exchange or Groups Administrator. Exchange access goes through a custom role group with exactly the needed roles.
- **Tenant grants are human decisions:** everything that touches the tenant (Graph roles, Exchange roles, app registration) is done once by an admin in bootstrap stage 2, never by the pipeline.
- **Protected groups stay out of reach:** role-assignable groups and groups synced from on-prem AD are refused by the engine and cannot be written with the granted permissions anyway.

## Identities

Seven identities, five of them machines.

| Identity | Kind | Used by | Purpose |
| --- | --- | --- | --- |
| engine | User-assigned managed identity | Automation Account (runbooks) | Reads users and groups, writes group members, writes state and runs |
| api | User-assigned managed identity | Function App | Reads config and directory data, writes config, starts runbook jobs |
| maintenance | User-assigned managed identity | Automation Account (runbook Renew-SignInCertificate only) | Uploads the renewed sign-in certificate to the app registration |
| web | System-assigned managed identity | Static Web App | Reads the sign-in certificate from Key Vault |
| pipeline | Service principal with workload identity federation | Azure DevOps service connection | Deploys Azure resources |
| RDG sign-in | App registration (with app roles) | Static Web App sign-in | Lets IT staff sign in as Admin or Reader |
| Bootstrap admin | Person (Global Administrator, or Privileged Role + Application + Exchange Admin) | Bootstrap stage 2, once | Grants tenant permissions, creates the app registration |

## Permission matrix

Every right each identity holds. Anything not listed is not granted.

| Identity | Microsoft Graph | Exchange Online | Cosmos DB (data plane) | Azure (control plane) |
| --- | --- | --- | --- | --- |
| engine | User.Read.All, GroupMember.ReadWrite.All, Group.Create, Group.ReadWrite.All | Exchange.ManageAsApp + custom role group "RDG Engine" | Data Reader on `config`; Data Contributor on `state` and `runs` | Key Vault: none. Automation: none (it runs inside the account) |
| maintenance | Application.ReadWrite.OwnedBy (owner of the RDG sign-in app only) | none | none | Key Vault Certificate User on the app Key Vault, which holds only the sign-in certificate |
| api | User.Read.All, GroupMember.Read.All | none | Data Contributor on `config`; Data Reader on `state` and `runs` | Automation Job Operator on the Automation account; Automation Runbook Operator on the two sync runbooks; Storage Blob Data Owner on the functions storage account (host storage and reading its package) |
| web | none | none | none | Key Vault Certificate User on the app Key Vault, which holds only the sign-in certificate |
| pipeline | none | none | none | Contributor and Role Based Access Control Administrator (conditioned) on the RDG resource group; Storage Blob Data Contributor on the state container (stage 1) and the packages container (OpenTofu, from pipeline\_principal\_id); Key Vault Crypto User on the state key |
| RDG sign-in | User.Read (delegated, for sign-in only) | none | none | none |

Notes:

- Cosmos DB rights are SQL role assignments scoped to the container, not account-wide. Key auth is disabled, so these are the only way in.
- The api cannot write members. Sync now and previews go through the engine, so only one identity ever changes a group.
- The engine cannot write definitions. A compromised engine can't widen its own scope through `config`.

## Graph permissions

All application permissions, granted once by the bootstrap admin (admin consent) to the managed identities with a short script in bootstrap stage 2. Managed identities can't be granted through the portal.

| Permission | Who | Why |
| --- | --- | --- |
| User.Read.All | engine, api | Evaluate rules on user properties; resolve names in previews and the include/exclude pickers |
| GroupMember.ReadWrite.All | engine | Add and remove members of Security and M365 groups; read memberOf for groups the tool doesn't manage |
| Group.Create | engine | Create new Security and M365 groups. The display name with prefix, and the marker attribute, are set at creation |
| GroupMember.Read.All | api | Group search in the target picker and the memberOf autocomplete |
| Group.ReadWrite.All | engine | Rename on adopt and the marker attribute on adopted Entra groups. Granted in the MVP; narrowing it is a later-version task (see Later versions) |
| Application.ReadWrite.OwnedBy | maintenance | Update keyCredentials on the RDG sign-in app, of which it is the only service-principal owner. Reaches no other app |

Display names in the api (include and exclude users, the compare group) are read with `GET /users/{id}` and `/groups/{id}` in JSON `$batch` requests of 20. `directoryObjects/getByIds` would need Directory.Read.All, which RDG doesn't grant.

What is never granted:

- **RoleManagement.ReadWrite.Directory**: needed to change role-assignable groups. The tool refuses those groups instead.
- **Directory.ReadWrite.All** or any directory role: not needed.
- **AppRoleAssignment.ReadWrite.All**: would let RDG assign its own Admin and Reader roles from the web app, but the same permission can grant any app any Graph permission. Role assignment stays in Entra (see Sign-in).

On-prem synced groups are read-only in Entra anyway; the engine and the adopt picker exclude them.

## Exchange role group

The engine connects with `Connect-ExchangeOnline -ManagedIdentity` and the Exchange.ManageAsApp application permission. What it may run comes from one custom role group, "RDG Engine", created in bootstrap stage 2. RBAC for Applications isn't used: it covers mailbox data, not distribution-group cmdlets.

| Role | Needed for |
| --- | --- |
| Distribution Groups | New-DistributionGroup, Set-DistributionGroup, Add-/Remove-DistributionGroupMember |
| Security Group Creation and Membership | Mail-enabled security groups, and `-BypassSecurityGroupManagerCheck` so the engine needn't be listed as owner |
| View-Only Recipients | Get-EXORecipient to resolve members and check that users have a mailbox or mail user |

No Organization Management, no Recipient Management. The service principal of the engine identity is the only member of the role group.

Limits to know:

- Exchange roles can't be scoped to managed groups only. Within Exchange the engine could change any distribution list; the engine code limits itself to the registry. This is the largest residual right and is named in the threat model.
- An optional management scope (recipient filter on the marker attribute) can narrow writes later; not in the MVP.

## Read-only installations

With `access_mode = read-only`, stage 2 grants only:

- **engine:** User.Read.All, GroupMember.Read.All; Exchange.ManageAsApp with a role group holding only View-Only Recipients.
- **api:** unchanged (it never writes to the tenant).
- **maintenance:** unchanged (it only touches the RDG sign-in app).

No Group.Create, GroupMember.ReadWrite.All or Group.ReadWrite.All, and no Exchange write roles. Switching to `read-write` reruns stage 2, which adds the write grants; switching back removes them.

## Sign-in

The Static Web App uses a custom Entra provider backed by the "RDG sign-in" app registration.

- **Single tenant.** The issuer is `https://login.microsoftonline.com/<tenant-id>/v2.0`; accounts from other tenants are refused.
- **Assignment required** on the enterprise app. Only users or groups assigned to a role can sign in at all.
- **App roles Admin and Reader, groups as a deployment setting.** The adopter names one Entra group per role in the deployment settings (`admin_group_id`, `reader_group_id`). The bootstrap stage 2 script assigns the roles to those groups; if a setting is left empty it creates "RDG Admins" or "RDG Readers" instead. To change it later: adjust the setting and rerun the script, or edit the assignment under the enterprise app's Users and groups. It is not a web app setting, because assigning app roles from the app would need AppRoleAssignment.ReadWrite.All. The `rolesSource` function reads the roles claim from the token and maps it to Static Web Apps roles; routes and API calls check those roles.
- **Group assignment needs Entra ID P1.** Assigning a group to an app role needs Microsoft Entra ID P1 or P2. Without it, stage 2 warns and admins assign users directly under the enterprise app's Users and groups; the rest of RDG runs on Entra ID Free.
- **No client secret.** The registration uses a certificate held in Key Vault. The Static Web App reads it with its system-assigned identity through a Key Vault reference (`clientSecretCertificateKeyVaultReference`, thumbprint `*` so a renewed certificate is picked up).
- **Conditional Access applies.** Sign-in is ordinary Entra sign-in, so the tenant's MFA and device rules apply. A dedicated policy for the app is recommended, not required.
- **Session.** Static Web Apps cookie, 8 hours. Removing a role takes effect at the next sign-in.
- **Certificate renewal, automated in the MVP.** Key Vault creates the certificate self-signed with a 12-month lifetime and auto-renews it 60 days before expiry. A weekly runbook, Renew-SignInCertificate, runs as the "maintenance" identity:
  1. Reads the newest certificate version (public part only) from Key Vault.
  2. If the app registration lacks that key, adds it with a PATCH on keyCredentials, keeping the current key so sign-in never breaks.
  3. Removes keys that have expired. The Static Web App uses the newest version through thumbprint `*`. Alerts: the runbook failing, and the app's newest key expiring within 21 days (see Monitoring and Alerting). Bootstrap makes the maintenance identity owner of the sign-in app.

## Pipeline identity

The Azure DevOps service connection uses workload identity federation: no secret, no expiry. The bootstrap admin creates it in stage 1 (or Azure DevOps creates it automatically when the creator has the rights).

- **Contributor** on the RDG resource group: create and update every resource.
- **Role Based Access Control Administrator** on the same resource group, with a condition that allows only the roles OpenTofu assigns: Key Vault Certificate User, Automation Job Operator, Automation Runbook Operator, Storage Blob Data Owner and Storage Blob Data Contributor. Cosmos DB rights are data-plane SQL role assignments, which Contributor covers. It can't grant Owner or itself more.
- **Storage Blob Data Contributor** on the OpenTofu state container.
- **No Graph and no Exchange rights.** Tenant grants stay in bootstrap stage 2, run by a person. If a release ever needs a new Graph permission, the release notes say so and the admin grants it.
- Pipeline runs on `main` only, with an approval check on the production environment.

## Threat model

| Threat | What an attacker gets | Mitigation |
| --- | --- | --- |
| RDG Admin account compromised | Can change rules, so can add any user to any managed group, including groups used in security policies | MFA via Conditional Access; audit trail of every change with the signed-in user; change limit stops mass changes; Admin role kept to a small group |
| api identity compromised (code flaw in the Function App) | Can write definitions; the engine then applies them on the next tick | Same change limit and audit; api has no Graph or Exchange write rights; definitions only reach managed groups; ETags and input validation on every write |
| engine identity compromised | Can change members of any Security/M365 group (not role-assignable, not on-prem) and any distribution list | Managed identity has no secret to steal; only runbook code runs as it; Automation account has no user access beyond the pipeline; engine stays the one writer so its runs are fully logged |
| Pipeline compromised | Can deploy changed code that then runs as engine or api | Federation tied to one Azure DevOps project; branch policy and approval on `main`; no tenant rights on the pipeline itself |
| maintenance identity compromised | Can add a credential to the RDG sign-in app and sign in as that app; can create new app registrations it would own | The sign-in app holds only delegated User.Read, so an extra credential grants nothing in the tenant; new apps it creates get no permissions without admin consent; only one short runbook runs as it |
| Self-editable attributes in rules | A user changes their own attribute (e.g. via a profile tool) and enters a group | Rule reference warns which attributes users or HR tools can edit; recommend `extensionAttribute*` and HR-fed attributes only |
| Groups used for privileged access | Anyone who can edit a rule decides who passes a Conditional Access exclusion or gets an app role | Role-assignable groups refused; docs advise against managing CA exclusion groups with RDG; a list of blocked group IDs is planned for a later version |
| Reader sees more than needed | Member lists and rules of all managed groups | Acceptable for IT staff; Reader still has no write path |

Residual risk: whoever holds RDG Admin effectively controls membership of every managed group. Treat the Admin role like a group-management admin role.

## Decisions

1. **Group.ReadWrite.All** is granted to the engine in the MVP. Narrowing it is a later-version task.
2. **Admin and Reader groups** are a deployment setting, not hard-coded for HEKS. If none are named, bootstrap creates its own groups.
3. **Certificate renewal** is automated in the MVP: Renew-SignInCertificate and the maintenance identity.
4. **No blocked-groups list** in the MVP.

## Later versions

- Narrow the engine's group rights: drop Group.ReadWrite.All once rename and marker writes can be done another way, or go through an approval step.
- Exchange management scope on the marker attribute, so the engine can only write distribution lists it manages.
- A Settings list of group IDs RDG must never touch (for example Conditional Access exclusion groups).
