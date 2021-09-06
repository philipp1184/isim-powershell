<#
    .SYNOPSIS
        Powershell Module to interact with ISIM SOAP WebService
    .DESCRIPTION
        This Module creates PS Methods for the ISIM SOAP WebService to give Administrators
        the ability to script WebUI interactions.
#>




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
            $newObj.$pname = Copy-ISIMObjectNamespace $obj.$pname $targetNS
        }
    }
    return $newObj
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
    }
    process {
        do {
            Write-Host -NoNewline "."
            Start-Sleep 3
            $status = $script:request_prx.getRequest($script:rsession,$requestId)
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

        if($script:session -eq $null) {
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
    }
    process {

        $ldapFilter = "(erservicename=$name)"
        $container = Copy-ISIMObjectNamespace $script:rootContainer $service_ns
        $response = $service_prx.searchServices($ssession,$container,$ldapFilter)

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
    }
    process {
        $response = $container_prx.searchContainerByName($csession, $rootContainer, "AdminDomain", $name)
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
        $person_dn = $null;
        $ldapFilter = "(uid="+$uid+")";
        #$attrList = nul; # Optional, supply an array of attribute names to be returned.
        # A null value will return all attributes.
        $persons = $person_prx.searchPersonsFromRoot($script:psession, $ldapFilter, $attrList);

        if ( $persons.Count -ne 1 ) {
            Write-Host -ForegroundColor Red "Search Parameter uid=$uid has no unique results. Count: $($persons.Count)"
        } else {
            $person_dn = $persons.itimDN;
        }

        $person_dn

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
	    [string]$ou_name
    )

    Begin {
        $ErrorActionPreference = 'Stop'
    }

    Process {
        $isimuid = $cred.GetNetworkCredential().username
        $isimpwd = $cred.GetNetworkCredential().password

	    ## Initialize SOAP WSDL URLs
	    $script:isim_url = $isim_url;
	    $script:isim_wsdl_session=$isim_url+"/itim/services/WSSessionService/WEB-INF/wsdl/WSSessionService.wsdl";
	    $script:isim_wsdl_person=$isim_url+"/itim/services/WSPersonServiceService/WEB-INF/wsdl/WSPersonService.wsdl";
	    $script:isim_wsdl_searchdata=$isim_url+"/itim/services/WSSearchDataServiceService/WEB-INF/wsdl/WSSearchDataService.wsdl";
	    $script:isim_wsdl_account=$isim_url+"/itim/services/WSAccountServiceService/WEB-INF/wsdl/WSAccountService.wsdl";
	    $script:isim_wsdl_container=$isim_url+"/itim/services/WSOrganizationalContainerServiceService/WEB-INF/wsdl/WSOrganizationalContainerService.wsdl";
	    $script:isim_wsdl_service=$isim_url+"/itim/services/WSServiceServiceService/WEB-INF/wsdl/WSServiceService.wsdl";
	    $script:isim_wsdl_password=$isim_url+"/itim/services/WSPasswordServiceService/WEB-INF/wsdl/WSPasswordService.wsdl";
	    $script:isim_wsdl_request=$isim_url+"/itim/services/WSRequestServiceService/WEB-INF/wsdl/WSRequestService.wsdl";
        $script:isim_wsdl_role=$isim_url+"/itim/services/WSRoleServiceService/WEB-INF/wsdl/WSRoleService.wsdl";


        Try {
	    $script:session_prx = New-WebServiceProxy -Uri $isim_wsdl_session -ErrorAction stop # -Namespace "WebServiceProxy" -Class "Session"
	    $script:person_prx = New-WebServiceProxy -Uri $isim_wsdl_person  -ErrorAction stop # -Namespace "WebServiceProxy" -Class "Person"
	    $script:search_prx = New-WebServiceProxy -Uri $isim_wsdl_searchdata -ErrorAction stop # -Namespace "WebServiceProxy" -Class "Search"
	    $script:account_prx = New-WebServiceProxy -Uri $isim_wsdl_account -ErrorAction stop # -Namespace "WebServiceProxy" -Class "Account"
	    $script:container_prx = New-WebServiceProxy -Uri $isim_wsdl_container -ErrorAction stop # -Namespace "WebServiceProxy" -Class "Container"
	    $script:service_prx = New-WebServiceProxy -Uri $isim_wsdl_service -ErrorAction stop # -Namespace "WebServiceProxy" -Class "Service"
	    $script:password_prx = New-WebServiceProxy -Uri $isim_wsdl_password -ErrorAction stop # -Namespace "WebServiceProxy" -Class "Password"
	    $script:request_prx = New-WebServiceProxy -Uri $isim_wsdl_request -ErrorAction stop # -Namespace "WebServiceProxy" -Class "Request"
        $script:role_prx = New-WebServiceProxy -Uri $isim_wsdl_role -ErrorAction stop # -Namespace "WebServiceProxy" -Class "Role"
        }
        Catch {
            Write-Host -ForegroundColor Red "Could not load WSDL Information"
        }


	    $script:session_ns = $script:session_prx.GetType().Namespace
	    $script:person_ns = $script:person_prx.GetType().Namespace
	    $script:search_ns = $script:search_prx.GetType().Namespace
	    $script:account_ns = $script:account_prx.GetType().Namespace
	    $script:container_ns = $script:container_prx.GetType().Namespace
	    $script:service_ns = $script:service_prx.GetType().Namespace
	    $script:password_ns = $script:password_prx.GetType().Namespace
	    $script:request_ns = $script:request_prx.GetType().Namespace
        $script:role_ns = $script:role_prx.GetType().Namespace


	    # Login
	    $script:session = $script:session_prx.login($isimuid,$isimpwd)

        if($script:session -eq $null) {
            Write-Error "Could not Login to WebService" -ErrorAction Stop
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

	    # Clone Objects to fit Namespaces
	    $script:psession = Copy-ISIMObjectNamespace $script:session $person_ns
	    $script:asession = Copy-ISIMObjectNamespace $script:session $account_ns
	    $script:csession = Copy-ISIMObjectNamespace $script:session $container_ns
	    $script:ssession = Copy-ISIMObjectNamespace $script:session $service_ns
	    $script:pwsession = Copy-ISIMObjectNamespace $script:session $password_ns
	    $script:rsession = Copy-ISIMObjectNamespace $script:session $request_ns
	    $script:rlsession = Copy-ISIMObjectNamespace $script:session $role_ns

        $script:rootContainer = $container_prx.getOrganizations($script:csession) | Where-Object -Property "name" -EQ -Value $ou_name

    }

}

function Disconnect-ISIM {
    <#

    .SYNOPSIS
        Connect to ISIM SOAP WebService

    .DESCRIPTION
        Connect to ISIM SOAP WebService. Creates a Client Session.

    #>
    if($script:session -eq $null) {
        Write-Error "No Active Session. Please Connect first." -ErrorAction Stop
    }
    $script:session_prx.logout($script:session)


	# Clone Objects to fit Namespaces
	$script:psession = $null
	$script:asession = $null
	$script:csession = $null
	$script:ssession = $null
	$script:pwsession = $null
	$script:rsession = $null
	$script:rlsession = $null

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
    }
    process {

        $personDN = $wsperson.itimDN;

        $req = $person_prx.addRole($script:psession,$personDN,$roleDN,$null,$false,"no");

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
    }
    process {
        $personDN = $wsperson.itimDN;

        $req = $person_prx.removeRole($script:psession,$personDN,$roleDN,$null,$false,"no");

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
        [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName = $true,Position = 0)]
        [string]
        $RoleName
    )
    begin {
        Test-ISIMSession
    }
    process {
        $filter="(errolename=$($RoleName))"
        $script:role_prx.searchRoles($script:rlsession,$filter)
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
    }
    process {

        if($a_attr -eq $null) {
            $a_attr = @{}
        }

        $serviceDN = Get-ISIMServiceName2DN -name $service
        $personDN = $wsperson.itimDN

        $password = $script:password_prx.generatePasswordForService($script:pwsession,$serviceDN)
        $a_attr.Add("erpassword",$password);
        #$a_attr.Add("eraccountstatus","0");
        $a_attr.Add("owner",$personDN);

        $wsattr = $script:account_prx.getDefaultAccountAttributesByPerson($script:asession,$serviceDN,$personDN)

        if(-not ($a_attr -eq $null)) {
            $wsattr = Convert-Hash2WSAttr -hash $a_attr -namespace $script:account_ns -inAttr $wsattr
        }




        $req = $account_prx.createAccount($asession, $serviceDN, $wsattr, $null, $false, "none")

        Wait-ForRequestCompletion($res.requestId);
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
    }
    process {


        $result = @{ 'password' = $null; 'services' = $null }


        $personDN = $wsperson.itimDN

        $accounts = $script:person_prx.getAccountsByOwner($script:psession,$personDN)
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
        $LDAPFilter
    )
    begin {
        Test-ISIMSession
    }
    process {

        if( $LDAPFilter -is [string] -and $LDAPFilter -like "(*)" ) {
            $person = $script:person_prx.searchPersonsFromRoot($script:psession,$LDAPFilter,$null)
        } else {
            $p_dn = Get-ISIMPersonUID2DN -uid $Uid
            if( -not ($p_dn -eq $null) ) {
                $person = $script:person_prx.lookupPerson($script:psession,$p_dn)
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

    try {
        $wsattr = Convert-Hash2WSAttr -hash $attr -namespace $script:person_ns
        $req = $script:person_prx.modifyPerson($script:psession,$wsperson.itimDN,$wsattr,$null,$false,"none")

        Wait-ForRequestCompletion($req.requestId);

    } catch {
        Write-Host -NoNewline "Update User Error '$($wsperson.name)': "
        Write-Host -ForegroundColor red $_.Exception.InnerException.Message
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
    process {

        $ou_search = $script:container_prx.searchContainerByName($script:csession,$script:rootContainer,$CProfile,$Container)
        if($ou_search.Length -eq 1) {
            $ou = Copy-ISIMObjectNamespace -obj $ou_search[0] -targetNS $script:person_ns
        }


        $wsperson = New-Object $($script:person_ns+".WSPerson")
        $wsperson.profileName = $Profile

        #$wsattr_mandatory = @{"cn"="common name";"sn"="surname"}
        $wsattr = Convert-Hash2WSAttr -hash $Attributes -namespace $script:person_ns

        $wsperson.attributes = $wsattr;



        $req = $script:person_prx.createPerson($script:psession,$ou,$wsperson,$null,$false,"none")

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
