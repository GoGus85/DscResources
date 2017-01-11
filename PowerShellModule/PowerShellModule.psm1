﻿enum ensure {
    absent
    present
}

enum scope {
    allusers
    currentuser
}

enum repositorytrust
{
    trusted
    untrusted
}

[DscResource()]
class PSModuleResource {

    [DscProperty(Key)]
    [string]$Module_Name

    [DscProperty(Mandatory)]
    [Ensure]$Ensure = [ensure]::present

    [DscProperty(Mandatory=$false)]
    [string]$RequiredVersion

    [DscProperty(Mandatory=$false)]
    [string]$MinimumVersion

    [DscProperty(Mandatory=$false)]
    [string]$MaximumVersion

    [DscProperty(Mandatory=$false)]
    [scope]$InstallScope = [scope]::allusers

    [DscProperty(Mandatory=$false)]
    [string]$RepositoryName = 'PSGallery'

    [PSModuleResource] Get() {
        
        $state = [hashtable]::new()
        $state.Module_Name = $this.Module_Name
        $Module = Get-Module -Name $this.Module_Name -ListAvailable -ErrorAction Ignore
        if ($Module) {
            $state.Ensure = [ensure]::present
        }
        else {
            $state.Ensure = [ensure]::absent
        }

        return [PSModuleResource]$state

    }


    [void] Set() {

        if ($this.Ensure -eq 'present') {
            try {
                $arguments = $this.GetVersionArguments()
                $arguments += @{"-Name" = $this.Module_Name; "-ErrorAction" = "Stop"; "-Repository" = $this.RepositoryName}
                Find-Module @arguments
            }
            catch {
                Write-Error -ErrorRecord $_
                throw $_
            }

            try {
                $arguments = $this.GetVersionArguments()
                $arguments += @{"-Name" = $this.Module_Name; "-Force" = $true; "-Scope" = $this.InstallScope; "-Repository" = $this.RepositoryName}
                Install-Module @arguments
            }
            catch {
                Write-Error -ErrorRecord $_
            }
        }
        elseif ($this.Ensure -eq 'absent') {
            $arguments = $this.GetVersionArguments()
            $arguments += @{"-Name" = $this.Module_Name; "-Force" = $true}
            Uninstall-Module @arguments
        }
        else {
            throw [System.ArgumentOutOfRangeException] "Value '$($this.Ensure)' of property Ensure is outside the range of allowed values"
        }
    }

    [bool] Test() {

        $modules = @()
        $modules += @(Get-Module -Name $this.Module_Name -ListAvailable -ErrorAction Ignore)
        $returnVal = $false

        Write-Verbose "The following versions of $($this.Module_Name) are installed"
        foreach ($module in $modules)
        {
            Write-Verbose "Module: $($this.Module_Name), Version: $($module.Version)"
        }

        # When no modules with that name were found
        if ($modules.Count -eq 0)
        {
            return ($this.Ensure -eq 'absent')
        }

        # We've found one or more matching modules, if neither RequiredVersion, MinimumVersion nor MaximumVersion is specified
        if ((-not $this.RequiredVersion) -and (-not $this.MinimumVersion) -and (-not $this.MaximumVersion))
        {
            return ($this.Ensure -eq 'present')
        }

        # We've found one or more modules, check if RequiredVersion is set
        if ($this.RequiredVersion)
        {
            $modules | Where-Object { [System.Version]$_.Version -eq [System.Version]$this.RequiredVersion } | % {
                $returnVal = ($this.Ensure -eq 'present')
            }        
        }

        # We've found one or more modules but RequiredVersion is not set, check MinimumVersion and MaximumVersion
        if ($this.MinimumVersion -and $this.MaximumVersion)
        {
            $modules | Where-Object { ([System.Version]$_.Version -ge [System.Version]$this.MinimumVersion) -and ([System.Version]$_.Version -le [System.Version]$this.MaximumVersion) } | % {
                $returnVal = ($this.Ensure -eq 'present')
            }
        }
        elseif ($this.MinimumVersion) {
            $modules | Where-Object { [System.Version]$_.Version -ge [System.Version]$this.MinimumVersion } | % {
                $returnVal = ($this.Ensure -eq 'present')
            }
        }
        elseif ($this.MaximumVersion) {
            $modules | Where-Object { [System.Version]$_.Version -le [System.Version]$this.MaximumVersion } | % {
                $returnVal = ($this.Ensure -eq 'present')
            }
        }

        return $returnVal
    }

    [hashtable] GetVersionArguments() {

        if ($this.RequiredVersion -and ($this.MaximumVersion -or $this.MinimumVersion))
        {
            throw [System.ArgumentException] "The RequiredVersion argument is mutually exclusive to the MaximumVersion and MinimumVersion"
        }        

        $versionArgs = [hashtable]::new()

        if ($this.RequiredVersion)
        { 
            $versionArgs.Add("-RequiredVersion", $this.RequiredVersion)
        }
        else {
            if ($this.MinimumVersion)
            {
                $versionArgs.Add("-MinimumVersion", $this.MinimumVersion)
            }
            if ($this.MaximumVersion)
            {
                $versionArgs.Add("-MaximumVersion", $this.MaximumVersion)
            }            
        }
        return $versionArgs            
    }
}

[DscResource()]
class PSModuleRepositoryResource {

    [DscProperty(Key)]
    [string]$RepositoryName

    [DscProperty(Mandatory)]
    [Ensure]$Ensure = [ensure]::present

    [DscProperty(Mandatory=$false)]
    [string]$RepositoryInstallationPolicy = [repositorytrust]::untrusted

    [DscProperty(Mandatory=$false)]
    [string]$RepositorySourceLocation

    [DscProperty(Mandatory=$false)]
    [string]$RepositoryPublishLocation

    [PSModuleRepositoryResource] Get() {
        $state = [hashtable]::new()
        $state.Module_Name = $this.RepositoryName
        return [PSModuleRepositoryResource]$state
    }

    [void] Set() {

        $repository = Get-PSRepository -Name $this.RepositoryName -ErrorAction Ignore

        if ($this.Ensure -eq 'present')
        {
            if ($repository)
            {
                Set-PSRepository -Name $this.RepositoryName -SourceLocation $this.RepositorySourceLocation -PublishLocation $this.RepositoryPublishLocation -InstallationPolicy $this.RepositoryInstallationPolicy                
            }
            else {
                Register-PSRepository -Name $this.RepositoryName -SourceLocation $this.RepositorySourceLocation -PublishLocation $this.RepositoryPublishLocation -InstallationPolicy $this.RepositoryInstallationPolicy
            }
        }
        elseif ($this.Ensure -eq 'absent') {
            Unregister-PSRepository -Name $this.RepositoryName
        }
        else {
            throw [System.ArgumentOutOfRangeException] "Value '$($this.Ensure)' of property Ensure is outside the range of allowed values"
        }
    }

    [bool] Test() {

        $repository = Get-PSRepository -Name $this.RepositoryName -ErrorAction Ignore

        if ($repository)
        {
            if ($this.Ensure -eq 'present')
            {
                if ($repository.InstallationPolicy -eq $this.RepositoryInstallationPolicy -and $repository.SourceLocation -eq $this.RepositorySourceLocation -and $repository.PublishLocation -eq $this.RepositoryPublishLocation)
                {
                    return $true
                }
            }
            return $false
        }
        else {
            return ($this.Ensure -eq 'absent')
        }
    }
}
