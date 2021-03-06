########################################################################################################
# !!! Make sure to change these settings   !!!
########################################################################################################

#for email notifications
$emailSMTP="smtp_server"  # smtp.myorg.com
$emailFrom="emailfrom@email.com"
$emailUseDefaultCredentials = $True #comment out this line if you do not want use current windows credentials of the account, this script is run under


##############################################################################################################################################################################################################
# FileCleaner utility
# Created by Borys Tyukin, 2012
##############################################################################################################################################################################################################
# Description:
#
# Powershell script created to enforce files retention rules on local and network folders.
# Script supports external configuration file to set up files cleanup rules and apply different actions to the files, matched specified criteria.
# More than one retention rule is supported for one folder.
# On script completion, email report can be sent and also log file can be stored.
# Make sure to used fixed font for email reports so they look better.
# Currently supported actions are: skip file, delete file and move file - see configuration file for detailed explanation and examples.
#
#
##############################################################################################################################################################################################################
#
# How to run this script from a bat file / cmd command shell
# -------------------------------------------
# powershell.exe -noprofile -ExecutionPolicy Bypass "& '\\networkshare\FileCleaner\filecleaner.ps1' -configFile '\\networkshare\FileCleaner\filecleaner.ini' -email youremail@email.com -report '\\networkshare\FileCleaner\filecleanerlog.csv'"
# EXIT %errorlevel%
#
# How to run this script from powershell console or PowerShell ISE:
# -------------------------------------------
# ."\\networkshare\FileCleaner\filecleaner.ps1" -configFile "\\networkshare\FileCleaner\filecleaner.ini" -email youremail@email.com -report "\\networkshare\FileCleaner\filecleanerlog.csv"
#
# -------------------------------------------
# Parameters:
#
# -configFile - Full path to a configuration file with retention rules
# -email      - Comma-delimited list of email addresses to send a notification email on script completion. E.g. -email name1@myorg.com,name2@myorg.com
# -report     - Full path to a file to save execution report to (csv file, which can be opened in Excel)
# -reportonly - Actions won't be applied to files, only a log/report will be produced. Useful for retention rules validation / analysis, before doing actual deletes/moving files.
# -hideRulesStats - Won't output statistics by every retention rule - will make execution report much shorter
#
##############################################################################################################################################################################################################

param (
     #Path to a config file with rules
     [parameter(Mandatory=$true)]
     [string]$configFile
     
     #Comma-delimited list of emails to send a notification on completion
    ,[parameter(Mandatory=$false)]
     [string[]]$email
     
     #Save file report to this file
    ,[parameter(Mandatory=$false)]
     [string]$report
    
     #Do not apply actions to files, only produce a report 
    ,[parameter(Mandatory=$false)]
     [switch]$reportonly

     #Do not output stats by rule
    ,[parameter(Mandatory=$false)]
     [switch]$hideRulesStats
)


########################################################################################################
# Do not change below
########################################################################################################

#stops further script execution on errors
$ErrorActionPreference = "Stop"

########################################################################################################
# FUNCTIONS DECLARATION
########################################################################################################  

#all scripts output will be written here so we can use that to save to a log file, email and output to console in a realtime
#output should be done using mylog filter
#examples 
#         "Process Step1" | mylog
#         "`nDoing {0} on {1}" -f $a, $b | mylog

$script:output = ""

#custom mylog filter to capture output in variable $script:output to use all the output to log,email etc.
filter mylog {
    $script:output+= $_+"`n"
    return $_
}

##########################################################################################################
# Parse-Rule function parses a line from config file to extract and validate parameters and values #
##########################################################################################################

Function Parse-Rule
{ 
Param(
     [string][Alias("tgt")]$targetFolder          #start folder to scan

    ,[string[]][Alias("sf")]$subFolders          #Array, comma-delimited list of subfolder name patterns. All subfolders will be processed by default. E.g. *download*, C:\TEMP*
    ,[string[]][Alias("xsf")]$excludeSubFolders   #Array, comma-delimited list of subfolder name patterns to exclude. E.g. *History*, C:\Documents*

    ,[string[]][Alias("f")]$files          #Array, comma-delimited list of file name patterns. All files by default. E.g. *.txt,*.dat
    ,[string[]][Alias("xf")]$excludeFiles   #Array, comma-delimited list of file name patterns to exclude. E.g. *.csv,*.log

    # expected format ^([0-9]{1,5})(hours|days|months|years)$
    ,[string][Alias("minmage")]$minModificationAge  #-minModificationAge (alias -minmage) - Include files, modified more than X hours/days/months/years ago. No space between X and time unit! E.g. -minmage10days
    ,[string][Alias("maxmage")]$maxModificationAge  #-maxModificationAge (alias -maxmage) - Include files, modified within last X hours/days/months/years. No space between X and time unit! E.g. -maxmage 2hours
    ,[string][Alias("mincage")]$minCreationAge      #-minCreationAge (alias -mincage) - Include files, created more than X hours/days/months/years ago. No space between X and time unit! E.g. -mincage 2years
    ,[string][Alias("maxcage")]$maxCreationAge      #-maxCreationAge (alias -maxcage) - Include files, created within last X hours/days/months/years. No space between X and time unit! E.g. -maxcage 1months

    # expected format ^([0-9]{1,20})(b|kb|mb|gb|tb)$
	,[string][Alias("mins")]$minSize             #-minSize (alias -mins) - Include files with file size more than X b/kb/mb/gb/tb. No space between X and size unit! E.g. -mins 10mb
    ,[string][Alias("maxs")]$maxSize             #-maxSize (alias -maxs) - Include files with file size less than X b/kb/mb/gb/tb. No space between X and size unit! E.g. -maxs 1tb

    ,[string][Alias("act")]$action  #action can be "skip","delete","move"
   
    ,[string][Alias("mt")]$moveto  #mandatory for -action move. Path to a folder to move files to
    
    ,[switch][Alias("tr")]$tree #Used with move action, will create subfolders in destination. If not passed, all files will be moved a single target directory and overwrite files with the same names        
) 
Process 
{ 
    #############################
    # Validate parameters passed
    #############################
    
    <#
    #print input params
    write-host $targetFolder
    write-host $subFolders
    write-host $excludeSubFolders
    write-host $files
    write-host $excludeFiles
    write-host $minModificationAge
    write-host $maxModificationAge
    write-host $minCreationAge
    write-host $maxCreationAge
    write-host $minSize
    write-host $maxSize
    write-host $action
    write-host $moveto
    #>   
    
    #Any command line argument that is NOT bound do a parameter is available in $args array, so if it is empty, all parameters were bound
    if ($args) { throw "Unknown parameters were passed!"}

    if (-NOT $targetFolder) { throw "Folder was not specified!" }
    
    if (-NOT $(Test-Path $targetFolder -PathType 'Container')) {throw "Folder $targetFolder does not exist!" }
    
    if ($minModificationAge -AND $minModificationAge -notmatch "^([0-9]{1,5})(seconds|minutes|hours|days|months|years)$") { throw "-minModificationAge should be specified as a whole number (1..99999) with a date/time unit name added in the end (seconds,minutes,hours,days,months or years). E.g. 90days or 2years"}
    if ($maxModificationAge -AND $maxModificationAge -notmatch "^([0-9]{1,5})(seconds|minutes|hours|days|months|years)$") { throw "-maxModificationAge should be specified as a whole number (1..99999) with a date/time unit name added in the end (seconds,minutes,hours,days,months or years). E.g. 90days or 2years"}
    if ($minCreationAge -AND $minCreationAge -notmatch "^([0-9]{1,5})(seconds|minutes|hours|days|months|years)$") { throw "-minCreationAge should be specified as a whole number (1..99999) with a date/time unit name added in the end (seconds,minutes,hours,days,months or years). E.g. 90days or 2years"}
    if ($maxCreationAge -AND $maxCreationAge -notmatch "^([0-9]{1,5})(seconds|minutes|hours|days|months|years)$") { throw "-maxCreationAge should be specified as a whole number (1..99999) with a date/time unit name added in the end (seconds,minutes,hours,days,months or years). E.g. 90days or 2years"}
                
    if ($minSize -AND $minSize -notmatch "^([0-9]{1,20})(b|kb|mb|gb|tb)$") { throw "-minSize should be specified as a whole number (up to 20 digits) with a unit of measure added in the end (b for bytes,kb for Kilobytes,mb for Megabytes, gb for Gigabytes and tb for Terabytes). E.g. 1Tb"}
    if ($maxSize -AND $maxSize -notmatch "^([0-9]{1,20})(b|kb|mb|gb|tb)$") { throw "-maxSize should be specified as a whole number (up to 20 digits) with a unit of measure added in the end (b for bytes,kb for Kilobytes,mb for Megabytes, gb for Gigabytes and tb for Terabytes). E.g. 1Tb"}

    if (!$action) {throw "-action parameter was not specified!"}    
    
    if ("skip","delete","move" -notcontains $action) {throw "-action parameter value is not recognized. Accepted values are skip, delete or move."}    
    
    if (($action -eq "move") -and (!$moveto)) {throw "-moveto parameter must be passed with -action move"}
    
    if (($moveto) -AND (-NOT $(Test-Path $moveto -PathType 'Container'))) {throw "Folder $moveto specified for -moveto parameter does not exist!"}
    
    ####################################################################################################
    # Create a rule - rule is a prebuilt expression that will be applied to every file during scanning
    # $file will be replaced later with an actual file object
    ####################################################################################################
        
    $exp_file_arr   = @() #array will hold all expressions for files     

    #################### Expression for subfolder names
    
    $exp_folder_arr = @() #array will hold all expressions for folders

    #subfolders to include
    $exp_subfldnames_inc = ""
    if ($subFolders) {
        foreach ($pattern in $subFolders) {
            $exp_subfldnames_inc += " -or (`$file.DirectoryName -like '$pattern')"
        }
        $exp_subfldnames_inc = "(" + $exp_subfldnames_inc.Substring($exp_subfldnames_inc.indexOf("(")) +")"
        $exp_folder_arr += $exp_subfldnames_inc
    }
    
    
    #subfolders to exclude
    $exp_subfldnames_excl = ""
    if ($excludeSubFolders) {
        foreach ($pattern in $excludeSubFolders) {
            $exp_subfldnames_excl += " -and (`$file.DirectoryName -notlike '$pattern')"
        }
        $exp_subfldnames_excl = "(" + $exp_subfldnames_excl.Substring($exp_subfldnames_excl.indexOf("(")) +")"
        $exp_folder_arr += $exp_subfldnames_excl
    }
        
    
    # Build final expression for folders
    
    if ($exp_folder_arr) {
        $exp_folder_final =""            
        if ($exp_folder_arr) {
            foreach ($exp in $exp_folder_arr) {
                $exp_folder_final += " -and $exp"
            }
            $exp_folder_final = "(" + $exp_folder_final.Substring($exp_folder_final.indexOf("(")) +")"
        }
    }        
    
    #################### Expression for file names    
    
    #files to look for
    $exp_filenames_inc = ""
    if ($files) {
        foreach ($pattern in $files) {
            $exp_filenames_inc += " -or (`$file.name -like '$pattern')"
        }
        $exp_filenames_inc = "(" + $exp_filenames_inc.Substring($exp_filenames_inc.indexOf("(")) +")"
        $exp_file_arr += $exp_filenames_inc
    }    
    
    
    #files to exclude
    if ($excludeFiles) {
        foreach ($pattern in $excludeFiles) {
            $exp_filenames_excl += " -and (`$file.name -notlike '$pattern')"
        }
        $exp_filenames_excl = "(" + $exp_filenames_excl.Substring($exp_filenames_excl.indexOf("(")) +")"
        $exp_file_arr += $exp_filenames_excl
    }
     

    #################### Expression for age
    
    #function returns part of age expression something like $((Get-Date).AddSeconds(-20))
    Function Get-AgeExpression 
    { 
        Param([string]$ageParam)
                
        $regex = "^([0-9]{1,5})(seconds|minutes|hours|days|months|years)$"        
        $null = $ageParam -match $regex #provide automatic arrays $matches
        $age=[int64]$matches[1]
        $unit=$matches[2]               
        
        switch ($unit) { 
            "seconds"  { "`$((Get-Date).AddSeconds(-$age))"}             
            "minutes"  { "`$((Get-Date).AddMinutes(-$age))"}             
            "hours"    { "`$((Get-Date).AddHours(-$age))"}             
            "days"     { "`$((Get-Date).AddDays(-$age))"}             
            "months"   { "`$((Get-Date).AddMonths(-$age))"}             
            "years"    { "`$((Get-Date).AddYears(-$age))"}             
        } #end of switch
        
    }
    
    if ($minCreationAge) { $exp_file_arr += "(`$file.CreationTime -lt $(Get-AgeExpression $minCreationAge))" }
    if ($maxCreationAge) { $exp_file_arr += "(`$file.CreationTime -gt $(Get-AgeExpression $maxCreationAge))" }
    
    if ($minModificationAge) { $exp_file_arr += "(`$file.LastWriteTime -lt $(Get-AgeExpression $minModificationAge))" }
    if ($maxModificationAge) { $exp_file_arr += "(`$file.LastWriteTime -gt $(Get-AgeExpression $maxModificationAge))" }
                               
    #################### Expression for size

    $regex = "^([0-9]{1,20})(b|kb|mb|gb|tb)$"
                
    if ($minsize) {    

        $null = $minSize -match $regex #provide automatic arrays $matches
        $size=[int64]$matches[1]
        $unit=$matches[2]
        
        switch ($unit) { 
            "b"  { $minSizeBytes = $size} 
            "kb" { $minSizeBytes = $size * [math]::pow(2,10)} 
            "mb" { $minSizeBytes = $size * [math]::pow(2,20)} 
            "gb" { $minSizeBytes = $size * [math]::pow(2,30)} 
            "tb" { $minSizeBytes = $size * [math]::pow(2,40)} 
        } #end of switch
        
    }#end of if minsize

    if ($maxsize) {    

        $null = $maxSize -match $regex #provide automatic arrays $matches
        $size=[int64]$matches[1]
        $unit=$matches[2]
        
        switch ($unit) { 
            "b"  { $maxSizeBytes = $size} 
            "kb" { $maxSizeBytes = $size * [math]::pow(2,10)} 
            "mb" { $maxSizeBytes = $size * [math]::pow(2,20)} 
            "gb" { $maxSizeBytes = $size * [math]::pow(2,30)} 
            "tb" { $maxSizeBytes = $size * [math]::pow(2,40)} 
        } #end of switch
        
    }#end of if maxsize
    
    
    #create expression for size
    
    if ($minSizeBytes) {
        $exp_file_arr += "(`$file.Length -ge $minSizeBytes)"
    }

    if ($maxSizeBytes) {
        $exp_file_arr += "(`$file.Length -le $maxSizeBytes)"
    }    

    #################### Build final expression for files
    
    $exp_file_final =""            
    if ($exp_file_arr) {
        foreach ($exp in $exp_file_arr) {
            $exp_file_final += " -and $exp"
        }
        $exp_file_final = "(" + $exp_file_final.Substring($exp_file_final.indexOf("(")) +")"
    }
    
    ################### Return function results - target (start) folder and a rule expression for it
    $result = @{};
    $result.targetFolder = $targetFolder
    $result.fileRuleExpression = $exp_file_final
    $result.folderRuleExpression = $exp_folder_final
    
    if ($exp_file_final -and $exp_folder_final) { $result.ruleExpression = "( $exp_folder_final -and $exp_file_final )" }
    else { $result.ruleExpression = "$exp_folder_final$exp_file_final" }
    
    
    $result.action = $action
    if ($moveto) {$result.action_param1 = $moveto}
    
    if ($tree) {$result.action_param2 = $tree}
            
    $result

} # end of Process block
} # end of Parse-Rule function


###############################################################################################################
# Scan-Folder function will scan folders starting from $targetpath and apply all retention rules to the files
###############################################################################################################

function Scan-Folder { 
  
param(
 [string]$targetFolder
,[string]$folderRuleExpression
)
   
process
{            
    #Write-Host "Scanning $targetFolder"               
         
    try {
        $currentdir = New-Object system.IO.DirectoryInfo $targetFolder
    
        $subdirs = $currentdir.GetDirectories()
        
        #run Scan-Folder recursively if there are subfolders
        if ($subdirs) {            
            foreach ($subdir in $subdirs) { 
                Scan-Folder $subdir.FullName 
            }
        }

        ####  Process files now in the current folder
                      
        #  1. If a current folder has been processed already (check folder cache), we are done here and exit from a function 
        if ($foldersCache.contains($currentdir.FullName)) { return }
        
        $script:counter_foldersScannedTotal = $script:counter_foldersScannedTotal + 1

        #"found $($currentdir.FullName)"
        
        #  2. look through all the rules using priority - apply action to a file
        
        $files = $currentdir.GetFiles()
        
        $targetSubDir = "" #will be used for move with tree action
        
        if ($files) {
                        
            foreach ($file in $files) {
                
                #"   $($file.FullName)"
                
                $file_rule = "no match"
                $file_action = "N/A"
                $file_action_param1 = ""
                $file_action_param2 = ""
                
                #loops through all the rules to match to a file
                                
                for ($i=0; $i -lt $rules_arr.length; $i++) {
                                                
                    if ($currentdir.FullName -notlike $($rules_arr[$i].targetFolder+"*") ) { continue } #check if a rule can be applied to this folder
                
                    #test rule expression on a file
                    #"         Testing $($rules_arr[$i].ruleExpression)"

                    $isRuleMatch = ""
                    $cmd = $($rules_arr[$i].ruleExpression)
 
                    if($cmd) { $isRuleMatch = Invoke-Expression $cmd }
                    else {$isRuleMatch = $true} #if no filtering was defined
                                        
                    #if a rule matched to a file, exit from a loop. Because rules array in a reverse order, the rule defined last in config, will be applied
                    if ($isRuleMatch) {
                        #"         Matched a rule $($rules_arr[$i].priority), action = $($rules_arr[$i].action)"
                        
                        $file_rule = $($rules_arr[$i].ruleDefinition)
                        $file_action = $($rules_arr[$i].action)
                        $file_action_param1 = $($rules_arr[$i].action_param1)
                        $file_action_param2 = $($rules_arr[$i].action_param2)
                        
                        #log counters
                        $script:counter_filesMatchedTotal = $script:counter_filesMatchedTotal + 1
                        $script:counter_filesMatchedSize = $script:counter_filesMatchedSize + $file.Length

                        #created a hash with counters if it was not created yet
                        if (!$rules_arr[$i].counters) {
                            $rules_arr[$i].counters = @{filesCount = 0 ; Size = 0}
                        }
                        
                        $rules_arr[$i].counters.filesCount = $rules_arr[$i].counters.filesCount + 1
                        $rules_arr[$i].counters.Size = $rules_arr[$i].counters.Size + $file.Length
                                                
                        #counters by action
                        if (!$script:counters_byaction["$($rules_arr[$i].action)"]) {                                                    
                            $script:counters_byaction.Add($($rules_arr[$i].action), @{filesCount = 0 ; size = 0} )                            
                        }

                        $script:counters_byaction["$($rules_arr[$i].action)"]["filesCount"] = $script:counters_byaction["$($rules_arr[$i].action)"]["filesCount"] + 1
                        $script:counters_byaction["$($rules_arr[$i].action)"]["Size"] = $script:counters_byaction["$($rules_arr[$i].action)"]["Size"] + $file.Length
                                                
                        break                   
                    } #end of if ($isRuleMatch)
                } #end of for loop for rules_arr
                
                #at this point file action should be set so we can log/report this
                
                $script:counter_filesScannedTotal = $script:counter_filesScannedTotal + 1
                $script:counter_filesSizeTotal = $script:counter_filesSizeTotal + $file.Length                                
                                
                # if script is not run in a report only mode, apply action to a file
                if ((!$reportonly) -and ($file_action -ne "N/A")) {

                    try {

                        switch ($file_action) { 
                        
                            "skip"    { 
                                        #do nothing
                                      } 
                            
                            "delete"  { 
                                        #delete file
                                        Remove-Item $($file.fullname) -Force
                                      } 
                            
                            "move"    { #move file
                                        
                                        #use folders tree ( -tree parameters was passed)
                                        if ($file_action_param2) {
                                            
                                            #create a subfolder in destination first
                                            if (!$targetSubDir) {
                                            
                                                # take the current folder and strip root folder from it. E.g. C:\ftp\123 --> ftp\123
                                                
                                                $currentroot = $currentdir.Root.FullName.TrimEnd("\") #if there is a backslash in the end, remove it
                                                
                                                $subfolderFragment = $($currentdir.FullName).TrimStart($currentroot)
                                                
                                                # take target folder and add to target folder that fragment. E.g. X:\backup +\+ ftp\123, so the destination will be X:\backup\ftp\123
                                                
                                                $targetSubDir = $file_action_param1.TrimEnd("\") + "\" + $subfolderFragment.TrimStart("\").TrimEnd("\")
                                                #"$($file_action_param1  -replace "\\$","") | $subfolderFragment"
                                                                                            
                                                #create target subfolder
                                                $targetDir = New-Object system.IO.DirectoryInfo $targetSubDir                                                                                                
                                                if (!$targetDir.exists) {$targetDir.Create()}                                                
                                            }
                                            
                                            $dest = $targetSubDir + "\" + $file.name
                                            Move-Item $($file.fullname) -Destination $dest -Force
                                            
                                        }
                                        #move all files to one folder
                                        else {
                                            Move-Item $($file.fullname) -Destination $file_action_param1 -Force                                    
                                        }
                                        
                                      } #end of move file
                                       
                        } #end of switch ($file_action)

                    }
                    catch {
                        $script:counter_errors = $script:counter_errors + 1
                        "Error: Cannot apply action $file_action to $($file.fullname). $($_.Exception.Message)" | mylog
                    }                                                       

                } #end of if
                
                #write a line to a file report
                if ($report) {                                        
                    $outstring="`"$($currentdir.FullName)`",`"$($file.name)`",`"$($file.Extension)`",`"$($file.CreationTime -f `"yyyy-MM-dd H:mm:ss`")`",`"$($($(Get-Date) - $file.CreationTime).Days)`",`"$($file.LastWriteTime -f `"yyyy-MM-dd H:mm:ss`")`",`"$($($(Get-Date) - $file.LastWriteTime).Days)`",`"$($file.Length+0)`",`"$file_rule`",`"$file_action`",`"$file_action_param1`",`"$file_action_param2`""
                    $stream.WriteLine($outstring)
                }
                                                                 
            } #end of foreach $files
        
        }
        else {
            #do nothing folder is empty TODO log empty folders somehow to support their deletion?
        } #end of if ($files)
        
        $null = $foldersCache.Add($currentdir.FullName) #remember folder in foldersCache
        
        
    } #end of try
    catch {
        $script:counter_errors = $script:counter_errors + 1
        "Error $($_.Exception.Message)" | mylog
    }

  } # End of PROCESS function Scan-Folder block   
} # end function Scan-Folder




### Function formats size in bytes nicely
Function Get-FormattedNumber($size) 
{ 
  
 IF (!$size) 
 {
       "N/A"
 }
 ELSEIF($size -ge 1TB) 
   { 
      "{0:n2}" -f  ($size / 1TB) + " Tb" 
   } 
 ELSEIF($size -ge 1GB) 
    { 
      "{0:n2}" -f  ($size / 1GB) + " Gb" 
    } 
 ELSEIF($size -ge 1MB) 
    { 
      "{0:n2}" -f  ($size / 1MB) + " Mb" 
    } 
 ELSEIF($size -ge 1KB) 
    { 
      "{0:n2}" -f  ($size / 1KB) + " Kb" 
    } 
 ELSE 
    { 
      "$size bytes" 
    } 
    
} #end function Get-FormattedNumber


#*****************************   MAIN SECTION **********************************************************


########################################################################################################
# Parse config file
########################################################################################################

$config = @()    #will store lines from config file
$rules_arr = @() #will store parsed rules

# Read config file. Parse out each line to extract
# Target folder, parameters and values

$configFileLineNumber = 0

Get-Content $configFile | ForEach-Object {

  $configFileLineNumber++
  
  # Skip blank lines or comments. Return is the same here as 'continue'
  if (($($_.Trim()).Length -eq 0) -or ($_ -match "^\s*[#]"))
    {return}
      
  Try {
    #parse line and build an expression rule which will be applied to files during folder scannig
    $rule = Invoke-Expression $("Parse-Rule " + $_)
    $rule.ruleDefinition = $_
    $rule.priority = $configFileLineNumber #line number from config file will be used to prioritize rules if more than one rule applied to one file
    $rules_arr += $rule
  }
  Catch { 
    $message = "Error: Cannot parse line #{0} in $configFile : {1}" -f $configFileLineNumber,$_.Exception.Message
    throw ($message)
  }       

}  #end of Get-Content $configFile | ForEach-Object      

if (!$rules_arr) {throw "No rules defined in $configFile !"}

#reverse array order so rules defined last get priority
$null=[array]::Reverse($rules_arr)

#$rules_arr

#open connection to a file where report will be saved to
if ($report) {

    if (-NOT $(Test-Path $(Split-Path $report) -PathType 'Container')) {throw "Folder $(Split-Path $report) does not exist! Check the file path for -report parameter!" }
    
    try {
        # .NET streamwriter is much faster than out-file!
        $stream = [System.IO.StreamWriter] $report

        # output header
        $outstring="`"Folder Path`",`"File Name`",`"Extension`",`"Created On`",`"Creation Age, days`",`"Modified On`",`"Modification Age, days`",`"Size, bytes`",`"Rule Matched`",`"Action`",`"Action Parameter1`",`"Action Parameter2`""
        $stream.WriteLine($outstring)
    }
    catch {
        throw "Error: Cannot open file $report to save detailed report. Check if this file is opened already or check -report parameter! $($_.Exception.Message)"
    }
}    

########################################################################################################
# Loop through all target folders to process rules:
#   1. Start with the first rule - get the target folder, which will be scanned first
#   2. For every subfolder and root folder, get a full list of files and match with ALL the rules defined.
#      a) optimization - do not process files which were checked already
#      b) do not process already scanned folders? but what if exclude was used and not all subfolders were checked?
########################################################################################################

#Already processed folders will be stored in hash so they are not processed again
$foldersCache = new-object 'System.Collections.Generic.HashSet[string]'

#various counters for report
$script:counter_errors = 0
$script:counter_foldersScannedTotal = 0
$script:counter_filesScannedTotal = 0
$script:counter_filesSizeTotal = 0
$script:counter_filesMatchedTotal = 0
$script:counter_filesMatchedSize = 0

$script:counters_byaction=@{};

$StartDate = Get-date

"`n*** FileCleaner started at $(Get-Date) by $env:username, using configuration file $configFile ***" | mylog

#process all target folders, defined in config
foreach ($rule in $rules_arr) {    
    #"`nScan folder $($rule.targetFolder)`n"    
    Scan-Folder $rule.targetFolder $rule.folderRuleExpression    
}

"`n$script:counter_errors errors" | mylog
"$script:counter_foldersScannedTotal folders scanned total" | mylog
"$script:counter_filesScannedTotal files scanned total ($(Get-FormattedNumber $script:counter_filesSizeTotal))" | mylog
"$script:counter_filesMatchedTotal files matched rules ($(Get-FormattedNumber $script:counter_filesMatchedSize))" | mylog

"`n*** Report by Action" | mylog

$resultsObjArray = @()
foreach ($key in ($script:counters_byaction.keys)) {
    $resultsObj = New-Object Object
    $resultsObj | Add-Member -type NoteProperty -name Action -value $key
    $resultsObj | Add-Member -type NoteProperty -name Files -value $($script:counters_byaction[$key].filesCount+0)
    $resultsObj | Add-Member -type NoteProperty -name Size -value $(Get-FormattedNumber $script:counters_byaction[$key].size)
    $resultsObjArray += $resultsObj
}

$resultsObjArray | format-table  @{Label="Action";Expression={$_.Action};Width=50}, @{Label="Files";Expression={$_.Files};Width=10}, @{Label="Size";Expression={$_.Size};Width=10} -wrap  | Out-String | mylog

if (!$hideRulesStats) {
    "*** Report by Rule" | mylog

    $resultsObjArray = @()
    foreach ($rule in $rules_arr) {        
        $resultsObj = New-Object Object
        $resultsObj | Add-Member -type NoteProperty -name Rule -value $($rule.ruleDefinition)
        $resultsObj | Add-Member -type NoteProperty -name Files -value $($rule.counters.filesCount+0)
        $resultsObj | Add-Member -type NoteProperty -name Size -value $(Get-FormattedNumber $rule.counters.size+0)
        $resultsObjArray += $resultsObj
        #"{0,-150} {1,-10} {2,-15}" -f $($rule.ruleDefinition),$($rule.counters.filesCount), $(Get-FormattedNumber $rule.counters.size) | mylog
    }

    $resultsObjArray | format-table  @{Label="Rule";Expression={$_.Rule};Width=50}, @{Label="Files";Expression={$_.Files};Width=10}, @{Label="Size";Expression={$_.Size};Width=10} -wrap  | Out-String | mylog
 
}

$TimeToComplete=New-TimeSpan $StartDate $(Get-Date)
"*** Completed in $($TimeToComplete.Hours) hrs $($TimeToComplete.Minutes) minutes $($TimeToComplete.Seconds) seconds" | mylog

if ($report) {
    "`nDetailed file report saved to $report"  | mylog 
    $stream.close() 
}    

#send email notification
if ($email) {

    try {

        $emailFrom = $emailFrom
        $emailTo = $([string]::join(",", $email))
        $subject = "FileCleaner execution report"
        $body = $script:output | Out-String
        $smtpServer = $emailSMTP

        $smtp = new-object Net.Mail.SmtpClient($smtpServer)
        $smtp.UseDefaultCredentials = $emailUseDefaultCredentials
        
        $msg = new-object Net.Mail.MailMessage($emailFrom, $emailTo, $subject, $body)
        #$msg.IsBodyHTML = $true        
        $smtp.Send($msg)
    }
    catch {
        "Error: Cannot send email: $($_.Exception.Message)" | mylog
    }

}