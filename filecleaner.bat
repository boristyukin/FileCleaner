powershell.exe -noprofile -ExecutionPolicy Bypass "& '\\lkmaisigrid10.multihosp.net\lkmsftpstg01\FileCleaner\filecleaner.ps1' -configFile '\\lkmaisigrid10.multihosp.net\lkmsftpstg01\FileCleaner\filecleaner.ini' -email SSCIDataWarehouseTeam@AHSS.ORG -report '\\lkmaisigrid10.multihosp.net\lkmsftpstg01\FileCleaner\filecleanerlog.csv'"

EXIT %errorlevel%
pause