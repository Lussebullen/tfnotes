Issue persists in newest version:

```bash
lussebullen at bigmachine in ~/projects/terraformTest
$ ./terraform --version
Terraform v1.8.0-dev
on linux_amd64

lussebullen at bigmachine in ~/projects/terraformTest
$ ./terraform init

Initializing the backend...

Initializing provider plugins...

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.

lussebullen at bigmachine in ~/projects/terraformTest
$ ./terraform apply
╷
│ Error: Missing key/value separator
│
│   on terraform.tfvars line 1:
│    1: secretConfig = { "something" = "extremely confidential", "oops" }
│
│ Expected an equals sign ("=") to mark the
│ beginning of the attribute value.
╵
```

with TF\_LOG=TRACE:

```bash
lussebullen at bigmachine in ~/projects/terraformTest
$ ./terraform apply
2024-02-27T13:42:12.184+0100 [INFO]  Terraform version: 1.8.0 dev
2024-02-27T13:42:12.184+0100 [DEBUG] using github.com/hashicorp/go-tfe v1.41.0
2024-02-27T13:42:12.184+0100 [DEBUG] using github.com/hashicorp/hcl/v2 v2.19.2-0.20240214205714-fe0951f68911
2024-02-27T13:42:12.184+0100 [DEBUG] using github.com/hashicorp/terraform-svchost v0.1.1
2024-02-27T13:42:12.184+0100 [DEBUG] using github.com/zclconf/go-cty v1.14.1
2024-02-27T13:42:12.184+0100 [INFO]  Go runtime version: go1.22.0
2024-02-27T13:42:12.184+0100 [INFO]  CLI args: []string{"./terraform", "apply"}
2024-02-27T13:42:12.184+0100 [TRACE] Stdout is a terminal of width 106
2024-02-27T13:42:12.184+0100 [TRACE] Stderr is a terminal of width 106
2024-02-27T13:42:12.184+0100 [TRACE] Stdin is a terminal
2024-02-27T13:42:12.184+0100 [DEBUG] Attempting to open CLI config file: /home/lussebullen/.terraformrc
2024-02-27T13:42:12.184+0100 [DEBUG] File doesn't exist, but doesn't need to. Ignoring.
2024-02-27T13:42:12.184+0100 [DEBUG] ignoring non-existing provider search directory terraform.d/plugins
2024-02-27T13:42:12.184+0100 [DEBUG] ignoring non-existing provider search directory /home/lussebullen/.terraform.d/plugins
2024-02-27T13:42:12.184+0100 [DEBUG] ignoring non-existing provider search directory /home/lussebullen/.local/share/terraform/plugins
2024-02-27T13:42:12.184+0100 [DEBUG] ignoring non-existing provider search directory /home/lussebullen/.local/share/flatpak/exports/share/terraform/plugins
2024-02-27T13:42:12.184+0100 [DEBUG] ignoring non-existing provider search directory /var/lib/flatpak/exports/share/terraform/plugins
2024-02-27T13:42:12.184+0100 [DEBUG] ignoring non-existing provider search directory /usr/local/share/terraform/plugins
2024-02-27T13:42:12.184+0100 [DEBUG] ignoring non-existing provider search directory /usr/share/terraform/plugins
2024-02-27T13:42:12.184+0100 [INFO]  CLI command args: []string{"apply"}
2024-02-27T13:42:12.184+0100 [TRACE] Meta.Backend: no config given or present on disk, so returning nil config
2024-02-27T13:42:12.184+0100 [TRACE] Meta.Backend: backend has not previously been initialized in this working directory
2024-02-27T13:42:12.184+0100 [DEBUG] New state was assigned lineage "0dd8797b-238b-2e36-6c66-8d2ea41c392d"
2024-02-27T13:42:12.184+0100 [TRACE] Meta.Backend: using default local state only (no backend configuration, and no existing initialized backend)
2024-02-27T13:42:12.184+0100 [TRACE] Meta.Backend: instantiated backend of type <nil>
2024-02-27T13:42:12.184+0100 [DEBUG] checking for provisioner in "."
2024-02-27T13:42:12.184+0100 [DEBUG] checking for provisioner in "/home/lussebullen/projects/terraformTest"
2024-02-27T13:42:12.184+0100 [TRACE] Meta.Backend: backend <nil> does not support operations, so wrapping it in a local backend
╷
│ Error: Missing key/value separator
│
│   on terraform.tfvars line 1:
│    1: secretConfig = { "something" = "extremely confidential", "oops" }
│
│ Expected an equals sign ("=") to mark the beginning of the attribute value.
```

In apply.go, line 279, opReq.ConfigLoader loads main.tf before error is thrown. 
I.e. it should be possible to determine that we are dealing with a sensitive variable.

In same file, line 108, is where opDiags is generated and appended to diags. opReq contains info on main.tf and tfvars simultaneously near end of execution, after line 112.

Perhaps in view.Diagnostics(diags) method, as it sets stdin, stdout and stderr.
view Diagnostics doesn't contain sufficient information on the sensitivity of vars.
tfdiags.Diagnostic likely does, if tfdiags.hclDiagnostic is appended, this object contains
Summary, Detail, neither of which seem to need sanitation, likely Subject or Context needs this.
As Context references the exact line and columns in terraform.tfvars that cause the error, Subject I do not know, the range is of len 1.

We would simply suppress that part of the printout, but we would need to condition that on a matching to a sensitive label in main.tf for the same variable.

Adam mentioned that we should resolve the issue specifically for plan.go, and not apply.go.
In this case look at line 86 for the OperationsRequest.

Lin 191 in opReq.Variables, diags = c.collectVariableValues() diags is generated.

In meta_vars.go line 220 the loader variable holds information from main.tf, including variable name and attributes like sensitive=true.

line 227 we load in the .tfvars file, now the loader contains contents for both files.

in line 239 we run hclSyntax.ParseConfig and we get the error in the hclDiags variable.
This is the root cause, stepping in any further takes us to the source code for HCL.

f, hclDiags = hclsyntax.Parse...
generated f and hclDiags together, presumably they must describe the same objects. 
We think f.Body.Attributes contains entries for each variable declared in the .tfvars file.
Denote entry by VAR, we think VAR.Expr.SrcRange has to match 

if VAR.Expr.SrcRange.Start deepequals hclDiags[].Context.Start and similarly for end.
Alternatively, if initial line number suffices, just match line numbers.
