<#
    .SYNOPSIS
        Powershell Module to interact with ISIM SOAP WebService
    .DESCRIPTION
        This Module creates PS Methods for the ISIM SOAP WebService to give Administrators
        the ability to script WebUI interactions.
#>

Import-Module $PSScriptRoot\vendor\1ASOAP\Source\SOAPProxy\Modules\SOAPProxy\SOAPProxy.psm1 -Force | Out-Null


function Copy-ISIMObjectNamespace {
    <#

    .SYNOPSIS
        Helper Function to create WS Objects for the different WebServices

    .DESCRIPTION
        ISIM provided individual WebServices for Roles, Person, Session etc. Powershell with it´s New-WebServiceProxy
        Function will append Namespaces for each Service. This makes the objects inoperable between the other Services.
        To overcome this issue this Helper Function will copy an existing WS Object to another Namespace.

    .PARAMETER obj
        The Source Object which have to be copied

    .PARAMETER targetNS
        The Target Namespace for the new Object

    .OUTPUTS
        A Copy of the Object in Parameter obj with the Namespace as in Parameter targetNS


    #>
    param(
        [Parameter(Mandatory=$true)]
        $obj,
	    [Parameter(Mandatory=$true)]
	    [string]$targetNS
    )

    

    $myTypeName = $obj.getType().Name.Split("[")[0];

    if( $obj.getType().BaseType.Name -eq "Array" ) {
        $tmp_array = @();
        
        $obj | % {
            $tmp1 = Copy-ISIMObjectNamespace $_ $targetNS;
            $tmp_array += $tmp1;
        }

        return $tmp_array;




    } 

    $newObj = New-Object ( $targetNS+"."+$myTypeName)

    $obj.psobject.Properties | % {
        $pname = $_.Name
        if ( $_.TypeNameOfValue.StartsWith("System.") ) {
            if( $newObj.psobject.Properties.Item($pname) -ne $null ) {
                $newObj.$pname = $_.Value
            } else {
                Write-Host -ForegroundColor Yellow "Property $pname Could not be set"
            }
        } else {
            if ( !$newObj.$pname ) {
                 $newObj.$pname = New-Object ( $targetNS+"."+($_.TypeNameOfValue.Split(".")[-1].Split("[")[0]))
            }

            if($obj.$pname -ne $null) {
                $newObj.$pname = Copy-ISIMObjectNamespace $obj.$pname $targetNS
            } else {
                $newObj.$pname = $null
            }
        }
    }
    return $newObj
}

function Convert-WSAttr2Hash {
    <#
    .SYNOPSIS
        Helper Function to manage WSAttr with Hash Tables

    .DESCRIPTION
        Helper Function to manage WSAttr with Hash Tables

    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory=$true)]
        [psobject]$wsattr
    )
    process {
        $hashMap = @{}

        $wsattr | ForEach-Object {
            $name = $_.name;
            $values = $_.values;

            $hashMap.Add($name, $values);


        }

        return $hashMap;

    }
}

function Convert-Hash2WSAttr {
    <#
    .SYNOPSIS
        Helper Function to manage WSAttr with Hash Tables

    .DESCRIPTION
        Helper Function to manage WSAttr with Hash Tables. Will generate an WSAttr Object by adding Values from a Hash Table.

    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$hash,
        [Parameter(Mandatory=$true)]
        [string]$namespace,
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        $inAttr
    )
    process {


        if ( $inAttr -NE $null ) {
            $wsattr_array = $inAttr;

            $hash.GetEnumerator() | ForEach{
                $prop_name = $_.name;
                $prop_value = $_.value;

	            if ( ( $wsattr_array | Where-Object { $_.name -eq $prop_name }).Count -eq 1 ) {
		            ( $wsattr_array | Where-Object { $_.name -eq $prop_name }).values = $prop_value
	            } else {
                    $wsattr = New-Object ($namespace+".WSAttribute")
                    $wsattr.name = $prop_name
                    $wsattr.values +=  $prop_value
                    $wsattr_array += $wsattr
                }

            }

        } else {
            $wsattr_array = @();
            $hash.GetEnumerator() | ForEach{
                $wsattr = New-Object ($namespace+".WSAttribute")
                $wsattr.name = $_.name
                $wsattr.values +=  $_.value
                $wsattr_array += $wsattr
            }
        }



        return $wsattr_array;
    }

}

function Wait-ForRequestCompletion {
    <#

    .SYNOPSIS
        Helper Function to Wait until a Request ist finished

    .DESCRIPTION
        Helper Function to Wait until a Request ist finished

    #>
    param (
        [Parameter(Mandatory=$true)]
        [long]$requestId
    )
    begin {
        Test-ISIMSession
        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:request_ns
    }
    process {
        do {
            Write-Host -NoNewline "."
            Start-Sleep 3
            $status = $script:request_prx.getRequest($session,$requestId)
        } while( $status.processState -ne "C" )
        Write-Host "Finished"
    }
}

function Test-ISIMSession {
    <#

    .SYNOPSIS
        Check if an established WS connection exists.

    .DESCRIPTION
        Check if an established WS connection exists.

    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param ()
    process {

        if($ISIMConnection.ISIMSession -eq $null) {
            Write-Error "No Active ISIM WS Session" -ErrorAction Stop
        }


    }
}

function Get-ISIMServiceName2DN {
    <#

    .SYNOPSIS
        Get DN of a Service by its Name

    .DESCRIPTION
        Get DN of a Service by its Name

    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory=$true)]
        [string]$name
        )
    begin {
        Test-ISIMSession

        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:service_ns
    }
    process {

        $ldapFilter = "(erservicename=$name)"
        $container = Copy-ISIMObjectNamespace $script:rootContainer $service_ns
        $response = $service_prx.searchServices($session,$container,$ldapFilter)

        $response.itimDN;
    }
}

function Get-ISIMContainerName2DN {
    <#

    .SYNOPSIS
        Get DN of a Container by its Name

    .DESCRIPTION
        Get DN of a Container by its Name
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory=$true)]
        [string]$name
        )
    begin {
        Test-ISIMSession
        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:container_ns
    }
    process {
        $response = $container_prx.searchContainerByName($session, $rootContainer, "AdminDomain", $name)
        $response.itimDN;
    }
}

function Get-ISIMPersonUID2DN {
    <#

    .SYNOPSIS
        Get a Person DN by providing a UserID

    .DESCRIPTION
        Get a Person DN by providing a UserID

    #>
    [OutputType([string])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [string]$uid
    )
    begin {
        Test-ISIMSession
        
    }
    process {

        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:person_ns

        $person_dn = $null;
        $ldapFilter = "(uid="+$uid+")";
        #$attrList = nul; # Optional, supply an array of attribute names to be returned.
        # A null value will return all attributes.
        $persons = $person_prx.searchPersonsFromRoot($session, $ldapFilter, $attrList);

        if ( $persons.Count -ne 1 ) {
            Write-Host -ForegroundColor Red "Search Parameter uid=$uid has no unique results. Count: $($persons.Count)"
        } else {
            $person_dn = $persons.itimDN;
        }

        $person_dn

    }
}

function Get-ISIMPersonRolesRole {
    <#

    .SYNOPSIS
        Add a Role to a Person

    .DESCRIPTION
        Add a Role to a Person

    #>
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=1)]
        [psobject]$wsperson
    )
    begin {
        Test-ISIMSession
        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:person_ns
    }
    process {

        $personDN = $wsperson.itimDN;

        $roles = $person_prx.getPersonRoles($session,$personDN);

        $roles;

    }

}



function Get-ISIMPersonsByFilter {
    <#

    .SYNOPSIS
        Get Persons by LDAP Filter

    .DESCRIPTION
        Get Persons by LDAP Filter

    #>
    [OutputType([psobject])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [string]$ldapFilter
    )
    begin {
        Test-ISIMSession
        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:person_ns
    }
    process {

        #$attrList = nul; # Optional, supply an array of attribute names to be returned.
        # A null value will return all attributes.
        $persons = $person_prx.searchPersonsFromRoot($script:person_session, $ldapFilter, $attrList);

        $persons;

    }
}

function Get-ISIMAccountsByOwnerUID {
    <#

    .SYNOPSIS
        Get Accounts by UserID

    .DESCRIPTION
        Get Accounts by UserID

    #>
   [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [string]$uid
    )
    begin {
        Test-ISIMSession
        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:person_ns
    }
    process {

        $person_dn = Get-ISIMPersonUID2DN -uid $uid

        $accounts = $person_prx.getAccountsByOwner($session,$person_dn);

        $accounts;

    }

}

function Connect-ISIM {
    <#

    .SYNOPSIS
        Connect to ISIM SOAP WebService

    .DESCRIPTION
        Connect to ISIM SOAP WebService. Creates a Client Session.

    #>
    param(
      [Parameter(Mandatory=$true)]
      [PSCredential]$Credential,
	    [Parameter(Mandatory=$true)]
	    [string]$isim_url,
	    [Parameter(Mandatory=$false)]
	    [string]$ou_name,
		[string]$auth_mode = "direct" # direct = authorize via SOAP Login Method; basic = authorize via Basic Auth Header for e.g. Reverse Proxy SSO Implementations
    )

    Begin {
        $ErrorActionPreference = 'Stop'
    }

    Process {
        $isimuid = $Credential.GetNetworkCredential().username
        $isimpwd = $Credential.GetNetworkCredential().password

        # Init Connection Variable
        $global:ISIMConnection = New-Object PSObject
        $global:ISIMConnection | Add-Member AuthMode $auth_mode
        $global:ISIMConnection | Add-Member Cookies $null
        $global:ISIMConnection | Add-Member ISIMSession $null

        $proxies = New-Object PSObject
        $global:ISIMConnection | Add-Member WSProxies $proxies

        ## WebService WSDL Map
        $script:ws_map = @{
                    "session" = "/WSSessionService/WEB-INF/wsdl/WSSessionService.wsdl";
                    "person" = "/WSPersonServiceService/WEB-INF/wsdl/WSPersonService.wsdl";
                    "searchdata" = "/WSSearchDataServiceService/WEB-INF/wsdl/WSSearchDataService.wsdl";
                    "account" = "/WSAccountServiceService/WEB-INF/wsdl/WSAccountService.wsdl";
                    "container" = "/WSOrganizationalContainerServiceService/WEB-INF/wsdl/WSOrganizationalContainerService.wsdl";
                    "service" = "/WSServiceServiceService/WEB-INF/wsdl/WSServiceService.wsdl";
                    "password" = "/WSPasswordServiceService/WEB-INF/wsdl/WSPasswordService.wsdl";
                    "request" = "/WSRequestServiceService/WEB-INF/wsdl/WSRequestService.wsdl";
                    "role" = "/WSRoleServiceService/WEB-INF/wsdl/WSRoleService.wsdl";
        }


        ## Initialize SOAP WSDL URLs
        $script:isim_url = $isim_url;
        foreach ($ws in $script:ws_map.GetEnumerator() ) {
            $v = $ws.Value
            $k = $ws.Name
            $url = $script:isim_url+"/itim/services"+$v

            $varname = "isim_wsdl_"+$k
            New-Variable -Scope 'Script' -Name $varname -Value $url -Force
        }





		if( $auth_mode -eq "direct" ) {

        Try {

                foreach ($ws in $script:ws_map.GetEnumerator() ) {
                
                    $k = $ws.Name

                    # Init Proxy
                    $varname = "isim_wsdl_"+$k
                    $url = Get-Variable -Scope 'Script' -Name $varname -ValueOnly
                    Initialize-SOAPProxy -Uri $url -NameSpace $k

                    # Get Proxy
                    $varname = $k+"_prx"
                    $proxy = Get-SOAPProxy -Uri $url
                    $proxy_ns = $proxy.GetType().Namespace
                    New-Variable -Scope 'Script' -Name $varname -Value $proxy

                    # Get NS
                    $varname = $k+"_ns"
                    New-Variable -Scope 'Script' -Name $varname -Value $proxy_ns

                }
        

            }
            Catch {
                Write-Host -ForegroundColor Red "Could not load WSDL Information"
            }



			# Login
			$script:session = $script:session_prx.login($isimuid,$isimpwd)
            $global:ISIMConnection.ISIMSession = $script:session_prx.login($isimuid,$isimpwd);

			if($script:session -eq $null) {
				Write-Error "Could not Login to WebService" -ErrorAction Stop
			}


            foreach ($ws in $script:ws_map.GetEnumerator() ) {
	            # Clone Objects to fit Namespaces
                $k = $ws.Name
                $var_ns = $k+"_ns"
                $var_prx_session = $k+"_session"
                $value_ns = Get-Variable -Scope 'Script' -Name $var_ns -ValueOnly
                $value = Copy-ISIMObjectNamespace $script:session $value_ns
                New-Variable -Scope 'Script' -Name $var_prx_session -Value $value

            }



		} elseif ( $auth_mode -eq "basic" ) {
			$user = $Credential.GetNetworkCredential().Username
			$pass = $Credential.GetNetworkCredential().Password

			$pair = "$($user):$($pass)"

			$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))

			$basicAuthValue = "Basic $encodedCreds"

			$Headers = @{
				Authorization = $basicAuthValue
			}

			$web_session = ""
            $url = $isim_url+"/itim/j_security_check?j_username=dummy&j_password=dummy"
			Invoke-WebRequest -Uri $url -Method 'POST' -Headers $Headers -SessionVariable "web_session" | Out-Null

            #$web_session.Cookies.GetCookies($url)			

			if( 	$web_session -ne $null -and 
					$web_session.Cookies -ne $null -and 
					$web_session.Cookies.GetType().Name -eq "CookieContainer" 
			) {

                $global:ISIMConnection.Cookies = $web_session.Cookies;

                foreach ($ws in $script:ws_map.GetEnumerator() ) {
                
                    $k = $ws.Name      

                    # Init Proxy
                    $varname = "isim_wsdl_"+$k
                    $url = Get-Variable -Scope 'Script' -Name $varname -ValueOnly
                    $file = "$ENV:TEMP\$varname.wsdl"
                    (Invoke-WebRequest -Uri $url -Headers $Headers).Content | Out-File $file -Encoding utf8
                    Initialize-SOAPProxy -Uri $file -NameSpace $k -WarningAction SilentlyContinue

                    # Get Proxy
                    $varname = $k+"_prx"
                    $proxy = Get-SOAPProxy -Uri $file
                    $proxy.CookieContainer = $global:ISIMConnection.Cookies
                    $proxy_ns = $proxy.GetType().Namespace
                    New-Variable -Scope 'Script' -Name $varname -Value $proxy -Force

                    # Get NS
                    $varname = $k+"_ns"
                    New-Variable -Scope 'Script' -Name $varname -Value $proxy_ns -Force


                }

				


			    # Login
			    $script:session = $script:session_prx.login($isimuid,$isimpwd)
                $global:ISIMConnection.ISIMSession = $script:session_prx.login($isimuid,$isimpwd);




                foreach ($ws in $script:ws_map.GetEnumerator() ) {
	                # Clone Objects to fit Namespaces
                    $k = $ws.Name
                    $var_ns = $k+"_ns"
                    $var_prx_session = $k+"_session"
                    $value_ns = Get-Variable -Scope 'Script' -Name $var_ns -ValueOnly
                    $value = Copy-ISIMObjectNamespace $global:ISIMConnection.ISIMSession $value_ns
                    New-Variable -Scope 'Script' -Name $var_prx_session -Value $value

                    $varname = $k+"_prx"
                    (Get-Variable -Scope "Script" -Name $varname -ValueOnly).CookieContainer = $global:ISIMConnection.Cookies
                }

				
			}
			
			
		} else {
			Write-Error "Unknown Authentication Method" -ErrorAction Stop
		}

        $script:isim_version = $script:session_prx.getItimVersion()
        $script:isim_fp = $script:session_prx.getItimFixpackLevel()
        $script:ws_target_type = $script:session_prx.getWebServicesTargetType()
        $script:ws_version = $script:session_prx.getWebServicesVersion()

        Write-Host "Successfully connected to ISIM SOAP Webservice" -ForegroundColor green

        Write-Host -NoNewline "ISIM Version:      "
        Write-Host -ForegroundColor yellow "$script:isim_version"

        Write-Host -NoNewLine "ISIM FP Level:     "
        Write-Host -ForegroundColor yellow "$script:isim_fp"

        Write-Host -NoNewLine "SOAP Target Type:  "
        Write-Host -ForegroundColor yellow "$script:ws_target_type"

        Write-Host -NoNewLine "SOAP Version:      "
        Write-Host -ForegroundColor yellow "$script:ws_version"



        $org = $container_prx.getOrganizations($script:container_session) | Where-Object -Property "name" -EQ -Value $ou_name

        if($org -eq $null) {
            $org_txt = $container_prx.getOrganizations($script:container_session) | Select -ExpandProperty name
            Write-Error "Organization $ou_name not found - Use one of the following: $org_txt"
        }

        if($org -ne $null -and $org.Count -gt 1) {
            $org_txt = $org | Select -ExpandProperty name
            Write-Error "Multiple Organizations Found: $org_txt"
        }

        $script:rootContainer = $org

    }

}

function Disconnect-ISIM {
    <#

    .SYNOPSIS
        Connect to ISIM SOAP WebService

    .DESCRIPTION
        Connect to ISIM SOAP WebService. Creates a Client Session.

    #>
    if($global:ISIMConnection.ISIMSession -eq $null) {
        Write-Error "No Active Session. Please Connect first." -ErrorAction Stop
    }
    $script:session_prx.logout($global:ISIMConnection.ISIMSession)


	# Clone Objects to fit Namespaces
	$script:person_session = $null
	$script:account_session = $null
	$script:container_session = $null
	$script:service_session = $null
	$script:password_session = $null
	$script:request_session = $null
	$script:role_session = $null

    $script:rootContainer = $null

    $script:session_ns = $null
	$script:person_ns = $null
	$script:search_ns = $null
	$script:account_ns = $null
	$script:container_ns = $null
	$script:service_ns = $null
	$script:password_ns = $null
	$script:request_ns = $null
    $script:role_ns = $null

    Write-Host -ForeGroundColor green "Successfully disconnected from ISIM SOAP Webservice"
}



function Add-ISIMRole {
    <#

    .SYNOPSIS
        Add a Role to a Person

    .DESCRIPTION
        Add a Role to a Person

    #>
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=1)]
        [psobject]$wsperson,
        [Parameter(Mandatory=$true,Position=2)]
        [string]$roleDN,
        [Parameter(Mandatory=$false,Position=3)]
        [bool]$wait=$true
    )
    begin {
        Test-ISIMSession
        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:person_ns
    }
    process {

        $personDN = $wsperson.itimDN;

        $req = $person_prx.addRole($session,$personDN,$roleDN,$null,$false,"no");

        if($wait) {
          Wait-ForRequestCompletion($req.requestId);
        }

    }

}

function Remove-ISIMRole {
    <#

    .SYNOPSIS
        Remove a Role to a Person

    .DESCRIPTION
        Remove a Role to a Person

    #>
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=1)]
        [psobject]$wsperson,
        [Parameter(Mandatory=$true,Position=2)]
        [string]$roleDN
    )
    begin {
        Test-ISIMSession
        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:request_ns
    }
    process {
        $personDN = $wsperson.itimDN;

        $req = $person_prx.removeRole($session,$personDN,$roleDN,$null,$false,"no");

        Wait-ForRequestCompletion($req.requestId);
    }
}

function Get-ISIMRole {
    <#

    .SYNOPSIS
        Get ISIM Roles by Role Name

    .DESCRIPTION
        Get ISIM Roles by Role Name

    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param (
        [Parameter(Mandatory = $false,ValueFromPipelineByPropertyName = $true,Position = 0)]
        [string]
        $RoleName,
        [Parameter(Mandatory=$false)]
        [string]
        $ldapFilter
    )
    begin {
        Test-ISIMSession
        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:role_ns
    }
    process {
        if($ldapFilter -ne $null) {
            $filter = $ldapFilter
        } else {
            $filter="(errolename=$($RoleName))"
        }
        $script:role_prx.searchRoles($session,$filter)
    }


}



function New-ISIMAccount {
    <#

    .SYNOPSIS
        Create new Accounts for a Person

    .DESCRIPTION
        Create new Accounts for a Person

    #>
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=1)]
        [psobject]$wsperson,
        [Parameter(Mandatory=$true,Position=2)]
        [string]$Service,
        [Parameter(Mandatory=$false,Position=3)]
        [hashtable]$a_attr
    )
    begin {
        Test-ISIMSession
        $psession = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:password_ns
        $asession = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:account_ns
    }
    process {

        if($a_attr -eq $null) {
            $a_attr = @{}
        }

        $serviceDN = Get-ISIMServiceName2DN -name $service
        $personDN = $wsperson.itimDN

        $password = $script:password_prx.generatePasswordForService($psession,$serviceDN)
        $a_attr.Add("erpassword",$password);
        #$a_attr.Add("eraccountstatus","0");
        $a_attr.Add("owner",$personDN);

        $wsattr = $script:account_prx.getDefaultAccountAttributesByPerson($asession,$serviceDN,$personDN)

        if(-not ($a_attr -eq $null)) {
            $wsattr = Convert-Hash2WSAttr -hash $a_attr -namespace $script:account_ns -inAttr $wsattr
        }




        $req = $account_prx.createAccount($asession, $serviceDN, $wsattr, $null, $false, "none")

        Wait-ForRequestCompletion($req.requestId);
    }
}

function Get-ISIMAccounts {
    <#

    .SYNOPSIS
        Create new Accounts for a Person

    .DESCRIPTION
        Create new Accounts for a Person

    #>
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=1)]
        [psobject]$wsperson
    )
    begin {
        Test-ISIMSession
        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:person_ns
    }
    process {


        $itimDN = $wsperson.itimDN;

        return $script:person_prx.getAccountsByOwner($script:person_session,$itimDN);

    }
}

function Remove-ISIMAccount {
    <#

    .SYNOPSIS
        Delete Account

    .DESCRIPTION
        Delete Account

    #>
    param (
        [Parameter(Mandatory=$true,Position=1)]
        [psobject]$account
    )
    begin {
        Test-ISIMSession
        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:account_ns
    }
    process {

        
        $req = $script:account_prx.deprovisionAccount($session, $account.itimDN, $null, $false, "Remove-ISIMAccount")
        if( -not ($req -eq $null) ) {
            Wait-ForRequestCompletion($req.requestId);
        }


    }
}

function Add-ISIMAccountToPerson {
    <#

    .SYNOPSIS
        Assign Account to Person

    .DESCRIPTION
        Assign Account to Person

    #>
    param (
        [Parameter(Mandatory=$true,Position=1)]
        [psobject]$account,
        [Parameter(Mandatory=$true,Position=2)]
        [psobject]$person
    )
    begin {
        Test-ISIMSession
        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:account_ns
    }
    process {

        # Copy Account Object Attributes to correct Namespace
        $accountNew = Copy-ISIMObjectNamespace -obj $account -targetNS $script:account_ns;

        # orhpan Account
        $script:account_prx.orphanSingleAccount($session,$accountNew.itimDN);
        sleep -Milliseconds 500
        # search new orhpaned itimDN
        $wssearcharg = New-Object ($script:account_ns+".WSSearchArguments")
        $wssearcharg.profile = $accountNew.profileName;
        $wssearcharg.filter = "(eruid=$($accountNew.name))";

        # do Search Task
        $account_search = $script:account_prx.searchAccounts($session, $wssearcharg);
        
        # Adopt orphaned Account to new Person
        $script:account_prx.adoptSingleAccount($session,$account_search.itimDN,$person.itimDN);
    }
}



function Set-ISIMPasswords {
    <#

    .SYNOPSIS
        Set Passwords for 1 or more Accounts on a Person

    .DESCRIPTION
        Set Passwords for 1 or more Accounts on a Person

    #>
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [psobject]$wsperson,
        [Parameter(Mandatory=$true)]
        [array]$services
    )
    begin {
        Test-ISIMSession
        $psession = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:person_ns
        $pwsession = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:password_ns
        $rsession = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:request_ns
    }
    process {


        $result = @{ 'password' = $null; 'services' = $null }


        $personDN = $wsperson.itimDN

        $accounts = $script:person_prx.getAccountsByOwner($psession,$personDN)
        $pwd_accounts = @()

        foreach ($a in $accounts) {

            if ( $services.Contains($a.serviceName)) {
                $pwd_accounts += $a.itimDN
                Write-Host $a.serviceName
                $result['services'] += @{ $a.serviceName = $a.name }
            }
        }

        $initial_pwd = $password_prx.generatePassword($pwsession,$pwd_accounts)

        $result['password'] = $initial_pwd;

        $res = $password_prx.changePassword($pwsession,$pwd_accounts,$initial_pwd)

        Wait-ForRequestCompletion($res.requestId);

        $status = $request_prx.getRequest($rsession,$res.requestId);

        Write-Host "Password SET Request finished with Status" $status.statusString



        $initial_pwd

    }

}

function Get-ISIMPerson {
    <#

    .SYNOPSIS
        Get ISIM Person by Uid or LDAP Filter

    .DESCRIPTION
        Get ISIM Person by Uid or LDAP Filter

    #>
    [CmdletBinding()]
    [OutputType([psobject])]

    [CmdletBinding(DefaultParameterSetName='Uid')]
    param
    (
        [string]
        [Parameter(ParameterSetName='Uid', Position=0)]
        $Uid,

        [string]
        [Parameter(ParameterSetName='LDAPFilter', Position=0)]
        $LDAPFilter,
        [string]
        [Parameter(ParameterSetName='DN', Position=0)]
        $DN
    )
    begin {
        Test-ISIMSession
        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:person_ns
    }
    process {

        if( $LDAPFilter -is [string] -and $LDAPFilter -like "(*)" ) {
            $person = $script:person_prx.searchPersonsFromRoot($session,$LDAPFilter,$null)
        } elseif( $DN -is [string] -and $DN -like "erglobalid=*" ) {
            $person = $script:person_prx.lookupPerson($session,$DN)
        } else {
            $p_dn = Get-ISIMPersonUID2DN -uid $Uid
            if( -not ($p_dn -eq $null) ) {
                $person = $script:person_prx.lookupPerson($session,$p_dn)
            }
        }


        return $person;


    }


}

function Update-ISIMPerson {
    <#

    .SYNOPSIS
        Update Person Attributes by providing a Hash Table

    .DESCRIPTION
        Update Person Attributes by providing a Hash Table

    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=1)]
        [psobject]$wsperson,
        [Parameter(Mandatory=$true,Position=2)]
        [hashtable]$attr
    )
    begin {
        Test-ISIMSession
        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:person_ns
    }
    process {
        try {
            $wsattr = Convert-Hash2WSAttr -hash $attr -namespace $script:person_ns
            $req = $script:person_prx.modifyPerson($session,$wsperson.itimDN,$wsattr,$null,$false,"none")

            Wait-ForRequestCompletion($req.requestId);

        } catch {
            Write-Host -NoNewline "Update User Error '$($wsperson.name)': "
            Write-Host -ForegroundColor red $_.Exception.InnerException.Message
        }
    }




}



function Get-ISIMService {
    <#

    .SYNOPSIS
        Get ISIM Services

    .DESCRIPTION
        Get ISIM Services

    #>
    [CmdletBinding()]
    [OutputType([psobject])]

    [CmdletBinding(DefaultParameterSetName='ServiceName')]
    param
    (
        [string]
        [Parameter(ParameterSetName='ServiceName', Position=0)]
        $Uid
    )
    begin {
        Test-ISIMSession
        $session = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:service_ns
    }
    process {

        $value_ns = $script:service_prx.GetType().Namespace
        $container = Copy-ISIMObjectNamespace $script:rootContainer $value_ns
        $services = $script:service_prx.searchServices($session,$container,"")

        return $services;


    }


}



<##

 TBD - New-ISIMPerson not working right now !

##>
function New-ISIMPerson {
    <#

    .SYNOPSIS
        Create Person

    .DESCRIPTION
        Create Person

    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param (
        [Parameter(Mandatory=$true,Position=1)]
        [string]$Container,
        [Parameter(Mandatory=$true,Position=2)]
        [string]$Profile,
        [Parameter(Mandatory=$true,Position=3)]
        [hashtable]$Attributes,
        [Parameter(Mandatory=$false,Position=4)]
        [string]$CProfile="AdminDomain"
    )
    begin {
        Test-ISIMSession
        $csession = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:container_ns
        $psession = Copy-ISIMObjectNamespace $ISIMConnection.ISIMSession $script:person_ns
    }
    process {

        $ou_search = $script:container_prx.searchContainerByName($csession,$global:rootContainer,$CProfile,$Container)
        if($ou_search.Length -eq 1) {
            $ou = Copy-ISIMObjectNamespace -obj $ou_search[0] -targetNS $script:person_ns
        }


        $wsperson = New-Object $($script:person_ns+".WSPerson")
        $wsperson.profileName = $Profile

        #$wsattr_mandatory = @{"cn"="common name";"sn"="surname"}
        $wsattr = Convert-Hash2WSAttr -hash $Attributes -namespace $script:person_ns

        $wsperson.attributes = $wsattr;

        


        $req = $script:person_prx.createPerson($psession,$ou,$wsperson,$null,$false,"none")

        if( -not ($req -eq $null) ) {
            Wait-ForRequestCompletion($req.requestId);
        }


    }
}

Export-ModuleMember -Function Copy-ISIMObjectNamespace
Export-ModuleMember -Function Convert-Hash2WSAttr
Export-ModuleMember -Function Wait-ForRequestCompletion
Export-ModuleMember -Function Test-ISIMSession
Export-ModuleMember -Function Get-ISIMServiceName2DN
Export-ModuleMember -Function Get-ISIMContainerName2DN
Export-ModuleMember -Function Get-ISIMPersonUID2DN
Export-ModuleMember -Function Connect-ISIM
Export-ModuleMember -Function Disconnect-ISIM
Export-ModuleMember -Function Add-ISIMRole
Export-ModuleMember -Function Remove-ISIMRole
Export-ModuleMember -Function Get-ISIMRole
Export-ModuleMember -Function New-ISIMAccount
Export-ModuleMember -Function Set-ISIMPasswords
Export-ModuleMember -Function Get-ISIMPerson
Export-ModuleMember -Function Update-ISIMPerson
Export-ModuleMember -Function New-ISIMPerson
Export-ModuleMember -Function Get-ISIMAccountsByOwnerUID
Export-ModuleMember -Function Convert-WSAttr2Hash
Export-ModuleMember -Function Get-ISIMPersonsByFilter
Export-ModuleMember -Function Add-ISIMAccountToPerson
Export-ModuleMember -Function Remove-ISIMAccount
Export-ModuleMember -Function Get-ISIMAccounts
Export-ModuleMember -Function Get-ISIMService
Export-ModuleMember -Function Get-ISIMPersonRolesRole