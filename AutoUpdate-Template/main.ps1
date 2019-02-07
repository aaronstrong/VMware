<#
    .SYNOPSIS
        Main script that calls VMTemplate-WindowsUpdate.ps1 function and sends needed
        parameters.

    .NOTES Author:  Aaron Strong
    .NOTES Site:    www.theaaronstrong.com
    .NOTES Twitter  @theaaronstrong.com

    .Purpose
        To update a Windows template in VMware
#>

cd $PSScriptRoot  # Change directory from which script is running

.\VMTemplate-WindowsUpdate.ps1 -template "Windows 2019" -longtimer 120