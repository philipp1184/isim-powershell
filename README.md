# isim-powershell
IBM Security Identity Manager Powershell Module

### Usage


```powershell
Import-Module .\isim.psm1
$cred = Get-Credential
Connect-ISIM -Credential $cred -isim_url "http://localhost:9080" -ou_name "Organization A" 
 
# Remove Role From User by UID
Get-ISIMPerson -UID "UserA" | Remove-ISIMRole -roleDN "erglobalid=1234567890123456789,ou=roles,erglobalid=00000000000000000000,ou=CORP,dc=de"

# Add Role From User by UID
Get-ISIMPerson -UID "UserA" | Add-ISIMRole -roleDN "erglobalid=1234567890123456789,ou=roles,erglobalid=00000000000000000000,ou=CORP,dc=de"


# Remove Role From User by LDAPFilter and RoleName
Get-ISIMPerson -LDAPFilter "(uid=UserA)" | Remove-ISIMRole -roleDN $((Get-ISIMRoleDN "Role B").itimDN)

# Add Role From User by LDAPFilter
Get-ISIMPerson -LDAPFilter "(uid=UserA)" | Add-ISIMRole -roleDN $((Get-ISIMRoleDN "Role B").itimDN)
 ```
