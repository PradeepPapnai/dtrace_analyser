    Function UploadDtrace
 {
    <#
    .SYNOPSIS 
    Upload dtrace files to SQL database. 

    .DESCRIPTION
    This function help us to upload entire dtrace (including rollover files) to SQL server.  
    
    .PARAMETER SQLServer
    Give the host name OR FQDN without quotes. 
    
    .PARAMETER DtracePath
    Locatoin of dtrace (eg. D:\TSElog\customer\VERITAS)
    
    .EXAMPLE
    UploadDtrace -SQLServer LABSQL -DtracePath E:\TseLogs\
    This will copy dtrace log from location E:\TseLogs\ and then upload to SQL server 'LABSQL'
    
    .EXAMPLE
    UploadDtrace -SQLServer LABSQL -Path E:\TseLogs\
    This will copy dtrace log from location E:\TseLogs\ and then upload to SQL server 'LABSQL'
    #>

    Param
    (
    # SQL server name 
    [Parameter(HelpMessage="Enter the name OR FQDN of SQL server")]
    [Alias('SQL')]
    [string]$SQLServer='Localhost'
    ,
    # Location of dtrace, It should be in extracted before using this tool. 
    [Parameter(Mandatory=$true,HelpMessage="Location of extracted dtrace files")]
    [Alias('Path')]
    [string]$DtracePath="E:\TseLogs\201_0003_211607_212008"
    )
    # Start time of uploading dtrace. 
    $StartTime = (Get-Date)

    # Create database if not exist otherwise ignore gracefully. 
    $CreateDB= "
    USE master
    DECLARE @DBname VARCHAR(100) ='DtraceReview'
    DECLARE @DBcreate varchar(max) ='CREATE DATABASE ' + @DBNAME
    --EXECUTE(@DBcreate)
    IF  NOT EXISTS (SELECT name FROM sys.databases WHERE name = @DBname)
	    BEGIN
	    EXECUTE(@DBcreate) 
	    END;
    GO
    "

    # Only re-create table if table does not exist otherwise truncate the existing table. 
    $TableCreation= "
    USE DtraceReview
    IF NOT EXISTS (SELECT * FROM [DtraceReview].sys.tables WHERE NAME = 'DtraceContent')
        CREATE TABLE DtraceContent
        (
		    [SeqNo] [BIGINT], 
		    [SeqTime] [Time],
		    [PID] [NVARCHAR](100),
		    [PName] [NVARCHAR] (100),
		    [PThread] [NVARCHAR] (100),
		    [EventType] [NVARCHAR] (100),
		    [MText] [NVARCHAR](MAX)
        )
       
    ELSE 
        TRUNCATE TABLE [DtraceReview].dbo.DtraceContent
    GO
    "
    $IndexCreation= "
    USE DtraceReview
    IF NOT EXISTS (	SELECT * FROM SYS.indexes  WHERE NAME = 'Index_Pthread')
	CREATE NONCLUSTERED INDEX [Index_Pthread]
            ON [dbo].[DtraceContent] ([PThread])
            INCLUDE ([SeqNo],[SeqTime],[PID],[PName],[MText])
    "

    #Both above queries will execute one by one. 
    $Queries = ($CreateDB, $TableCreation, $IndexCreation)     
    foreach ($Query in $Queries)
        {
        Write-Verbose -Message "Preparing SQL DB" 
        Invoke-Sqlcmd -ServerInstance $SQLServer -Query $Query
        }

    # Upload each Dtrace file of specified location to SQLDB using BCP command line tool. 
    $DTfiles=Get-ChildItem -Path $DtracePath -Name
    foreach ($File in $DTfiles)
        {
        $PATH=$DtracePath+'\'+$File
        $PATH
        Write-Verbose -Message "Uploading Dtrace file $($File)"
        bcp DtraceReview.dbo.DtraceContent in $PATH -c -r\n -T -S $SQLserver
        }

    # End time of script
    $EndTime = (Get-Date)

    # Display time taken during dtrace upload. 
    $TotalTime = "Total Elapsed Time for Dtrace file(/s) insertion : $(($Endtime-$StartTime).totalseconds) seconds"
    Write-Verbose -Message $TotalTime
    Write-Verbose -Message "Upload complete"
    
 } 
    
# Function for analyzing dtrace file. 
Function DTraceReview
{

    <#
    .SYNOPSIS 
    It helps to find out the idle time (delay) between two lines of the dtrace of a same thread.  

    .DESCRIPTION
    This function connects to SQL then fire queries to find out delay, events and all thread of various process.  
    
    .PARAMETER SQLServer
    Give the host name OR FQDN without quotes. 
    
    .PARAMETER OutFile
    Location of outfile HTML file
    
    .EXAMPLE
    DTraceReview -SQLServer LABSQL1 -OutFile c:\temp\review.html
    This will contact to sql server 'LABSQL1' and process the delay/events/process-thread and generate output in c:\temp\review.html.
    
    
    .EXAMPLE
    DTraceReview -SQL EVBL1 -Path C:\TEMP\review.html
    Same as above example but this time we are using alias of parameter. 
    #>

    PARAM
        (
        # SQL server name 
        [Parameter(HelpMessage="SQL server name")]
        [Alias('SQL')]
        [string]$SQLServer='Localhost'
        ,
        # Location HTML file 
        [Parameter(Mandatory=$true,HelpMessage="Location of output HTML file")]
        [Alias('Path')]
        [string]$OutFile="C:\temp\DtraceDelay.HTML"
        )

    # Get Start Time of analyze script. 
    $startDTM = (Get-Date)
    Write-Verbose -Message "Starting dtrace review command line"
    <# HTML page formatting start #>
    $a = "<style>"
    $a = $a + "BODY{background-color:peachpuff;font-family: Calibri; font-size: 12pt;}"
    $a = $a + "TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}"
    $a = $a + "TH{border-width: 1px;padding: 0px;border-style: solid;border-color: black;}"
    $a = $a + "TD{border-width: 1px;padding: 0px;border-style: solid;border-color: black;}"
    $a = $a + "</style>"

    # Query to get unique thread and assoicated PID & Process name. 
    $QueryThreads= “
    Use DtraceReview
    SELECT DISTINCT PTHREAD, PNAME, PID  FROM DtraceContent ORDER BY PNAME, PID”

    # Query to get all Events present in Dtrace files. 
    $queryEvents= “
    Use DtraceReview
    SELECT SeqNo, SeqTime, PID, PName, Pthread, Eventtype, MText FROM DtraceContent WHERE mtext like '%Event ID%'"

    # Execute above mentioned queries. 
    $ResultThreads=Invoke-Sqlcmd -ServerInstance $SQLServer -Query $QueryThreads -QueryTimeout 65535
    Write-Verbose -Message "Retriving all unique threads of uploaded dtrace from SQL DB "
    $ResultEvents=Invoke-Sqlcmd -ServerInstance $SQLServer -Query $queryEvents -QueryTimeout 65535
    Write-Verbose -Message "Retriving all event id generated during dtrace capture window"
    # Save output of above SQL queries to HTML fragement. 
    $fragThreads =$ResultThreads|Select-Object PTHREAD, PNAME, PID | ConvertTo-HTML -PreContent '<H2> All Processes and Thread</H2>'  -head $a |Out-String
    $fragEvents = $ResultEvents|Select-Object SeqNo, SeqTime, PID, PName, Pthread, Eventtype, MText | ConvertTo-HTML -PreContent '<H2>All Events of Dtrace Files</H2>'  -head $a |Out-String

    # Create array to hold all threads. Retriving using variable $ResultThreads 
    $groups=$ResultThreads| Select-Object PTHREAD, PNAME, PID

    # Create a blank body, it's requireed so the section of each thread can be accomated. 
    $Body = ""
    foreach ($thread in $groups.GetEnumerator())
    {
        $queryDelay=
        "
        DECLARE @ThreadID VARCHAR(100)='$($thread.Pthread)'
        USE DtraceReview
        SELECT SA.SeqNo, SA.SeqTime, SA.Pname, SA.PID, SA.PThread,SA.MText, IdleTime
        FROM 
        (
	        SELECT SeqNo, SeqTime, Pname, PID, PThread,MText,
	        DATEDIFF (SS, SeqTime,LEAD(SeqTime,1) OVER (PARTITION BY PID, Pthread ORDER BY SeqNo,PID,Pthread) ) AS IdleTime
	        FROM DtraceContent
	        WHERE PTHREAD =@ThreadID
        ) SA
        WHERE IdleTime>2
        ORDER BY IdleTime DESC"
        # If the delay is greater than 2 seconds then only report it to HTML. 
        # Version 2.0 will have configuration for same option via variable. 

        $ResultDelay=Invoke-Sqlcmd -ServerInstance $SQLServer -Query $queryDelay -QueryTimeout 65535
        Write-Verbose -Message "Anaylyzing Ideal time thread id $($thread.Pthread)"
        $countR=@($ResultDelay).Count

        # If the count of delay is greater than 2 then only report in output file, it will keep HTML output shorten. 
        # Version 2.0 will have configuration for same option
        if ($countR -gt 2)
            {
            $Body+="<H2>EV Process $($thread.PNAME) having ProcessID $($thread.PID) AND ThreadID $($thread.Pthread)  </H2>"
            $body+=$ResultDelay| Select-Object SeqNo, SeqTime, Pname, PID, PThread, MText, IdleTime |Convertto-Html -Fragment -AS Table
            }
     }

    # Get End Time
    $endDTM = (Get-Date)

    # Result total Elasped time in HTML file, it will helpful to know statistic for improvement
    $TotalTime = "Total Elapsed Time for Analyze the trace: $(($endDTM-$startDTM).totalseconds) seconds"
    #$Header = "<h1>Enterprise Vault Performance analyzer (EVPA 1.0)</h1>" #Does not work so removing. 

    # HTML output to file, it will overwrite existing file if exist
    ConvertTo-Html -Title "EVPA-Version 1.0" -Body $Body -PostContent $fragThreads,$fragEvents, $TotalTime |Out-File $OutFile
    Write-Verbose -Message "Converting results to HTML file"
    # Open HTML file once processing done. 
    Invoke-Item $OutFile
    Write-Verbose -Message "Opening analysed file in HTML format."
    $TotalTime
    Write-Verbose -Message "Work complete"
}

Function OutThread
{
   <#
    .SYNOPSIS 
    Export selected dtrace thread from SQL database 'DtraceReview' to File. 

    .DESCRIPTION
    This function helps to extract a single thread for review.  
    
    .PARAMETER $IhreadId 
    Give the without quote OR bracket, Eg 1112. 
    
    .PARAMETER $ThreadPath
    Locatoin of extracted thread without file name (eg. C:\TEMP)
    A extracted file 'Dtrace_Thread_1112.txt' will create in 'C:\TEMP'
    
    .EXAMPLE
    OutThread -ThreadID 1112 -ThreadPath c:\temp\
    This will extract thread 1112 from SQL adn create file 'Dtrace_Thread_1112.txt' in 'c:\temp'  
    
    .EXAMPLE
    OutThread -TID 1112 -Path c:\temp\
    Same with alias of given parameter.
    #>

    PARAM
        (
        [Parameter(HelpMessage="SQL server name")]
        [Alias('SQL')]
        [string]$SQLServer
        ,        
        # Enter Thread Id 
        [Parameter(Mandatory=$true,HelpMessage="Thread id, eg 1122")]
        [Alias('TId')]
        [string]$ThreadId
        ,
        # Output Location 
        [Parameter(Mandatory=$true,HelpMessage="Location of output file, eg c:\temp")]
        [Alias('Path')]
        [string]$ThreadPath
        )

    $DtPid='<'+$ThreadId+'>'
    $ThreadUNC=$ThreadPath  #+'\Dtrace_Thread_'+$ThreadId+'.txt'
    Write-Verbose -Message "Extracting Thread $($ThreadId) to File $($ThreadUNC)"
    BCP  "USE DtraceReview SELECT SeqNo,SeqTime,PID, PName,PThread,EventType,MText FROM DtraceContent WHERE PThread = '$($DtPid)'"  queryout $ThreadUNC -T -c -S $SQLServer
    Write-Verbose -Message "File Created successfully"
}

Function SearchText
{

    PARAM
        (
        [Parameter(HelpMessage="SQL server name")]
        [Alias('SQL')]
        [string]$SQLServer
        ,        
        # Enter Thread Id 
        [Parameter(Mandatory=$true,HelpMessage="Search key word, eg 'failed to open Admin Queue' without quote")]
        [Alias('TId')]
        [string]$SearchText
        ,
        # Output Location 
        [Parameter(Mandatory=$true,HelpMessage="Location of output file for search Results, eg c:\temp")]
        [Alias('Path')]
        [string]$SearchOutPath
        )

    $SEarchoutFile=$SearchOutPath
    Write-Verbose -Message "Searching'$SearchText' to File '$SEarchoutFile'"
    BCP  "USE DtraceReview SELECT SeqNo, SeqTime, PID, PName, Pthread, Eventtype, MText FROM DtraceContent WHERE mtext like '%$SearchText%'"  queryout $SEarchoutFile -T -c -S $SQLServer
    Write-Verbose -Message "File created successfully"

}
        
        #start form
        $app = New-Object -ComObject shell.Application
        Add-Type -AssemblyName System.Windows.Forms 
        Add-Type -AssemblyName System.Drawing 
    
        $MyForm = New-Object System.Windows.Forms.Form 
        $MyForm.Text="Analyser" 
        $MyForm.Size = New-Object System.Drawing.Size(540,350)
        $MyForm.StartPosition='CenterScreen'
 
 
        $mDtraceFolder = New-Object System.Windows.Forms.Label 
                $mDtraceFolder.Text="Dtrace Folder" 
                $mDtraceFolder.Top="100" 
                $mDtraceFolder.Left="25" 
                $mDtraceFolder.Anchor="Left,Top" 
                $mDtraceFolder.Hide()
        $mDtraceFolder.Size = New-Object System.Drawing.Size(120,28) 
        $MyForm.Controls.Add($mDtraceFolder) 

        $ThreadID = New-Object System.Windows.Forms.Label 
                $ThreadID.Text="Thread ID" 
                $ThreadID.Top="140" 
                $ThreadID.Left="25" 
                $ThreadID.Anchor="Left,Top" 
                $ThreadID.Hide()
        $ThreadID.Size = New-Object System.Drawing.Size(120,28) 
        $MyForm.Controls.Add($ThreadID) 


        $sThreadOut = New-Object System.Windows.Forms.Label 
                $sThreadOut.Text="Output File" 
                $sThreadOut.Top="175" 
                $sThreadOut.Left="25" 
                $sThreadOut.Anchor="Left,Top" 
                $sThreadOut.Hide()
        $sThreadOut.Size = New-Object System.Drawing.Size(120,28) 
        $MyForm.Controls.Add($sThreadOut) 

        $mSearchKeyword = New-Object System.Windows.Forms.Label 
                $mSearchKeyword.Text="Keyword" 
                $mSearchKeyword.Top="140" 
                $mSearchKeyword.Left="25" 
                $mSearchKeyword.Anchor="Left,Top" 
                $mSearchKeyword.Hide()
        $mSearchKeyword.Size = New-Object System.Drawing.Size(120,28) 
        $MyForm.Controls.Add($mSearchKeyword) 
         
 
        $mDtPath = New-Object System.Windows.Forms.TextBox 
                $mDtPath.Text="C:\Temp\" 
                $mDtPath.Top="100" 
                $mDtPath.Left="160" 
                $mDtPath.Anchor="Left,Top" 
                $mDtPath.Hide()
        $mDtPath.Size = New-Object System.Drawing.Size(200,28) 
        $MyForm.Controls.Add($mDtPath) 

        $mThreadIDText = New-Object System.Windows.Forms.TextBox 
                $mThreadIDText.Text="1111" 
                $mThreadIDText.Top="140" 
                $mThreadIDText.Left="160" 
                $mThreadIDText.Anchor="Left,Top" 
                $mThreadIDText.Hide()
        $mThreadIDText.Size = New-Object System.Drawing.Size(200,28) 
        $MyForm.Controls.Add($mThreadIDText) 

        $mKeyWordText = New-Object System.Windows.Forms.TextBox 
                $mKeyWordText.Text="" 
                $mKeyWordText.Top="140" 
                $mKeyWordText.Left="160" 
                $mKeyWordText.Anchor="Left,Top" 
                $mKeyWordText.Hide()
        $mKeyWordText.Size = New-Object System.Drawing.Size(200,28) 
        $MyForm.Controls.Add($mKeyWordText) 

        $mThreadOutText = New-Object System.Windows.Forms.TextBox 
                $htmlFolder="C:\Temp\"+'Dtrace_Thread_'
                $htmlFileName=$mThreadIDText.Text +'.txt'
                $mThreadOutText.Text=$htmlFolder+$htmlFileName
                $mThreadOutText.Top="175" 
                $mThreadOutText.Left="160" 
                $mThreadOutText.Anchor="Left,Top" 
                $mThreadOutText.Hide()
        $mThreadOutText.Size = New-Object System.Drawing.Size(200,28) 
        $MyForm.Controls.Add($mThreadOutText)

        $mSearchOutText = New-Object System.Windows.Forms.TextBox 
                $mSearchOutText.Text="C:\Temp"+'\Search_output_'+(Get-Date).tostring("yyyyMMddhhmm")+'.txt'
                $mSearchOutText.Top="175" 
                $mSearchOutText.Left="160" 
                $mSearchOutText.Anchor="Left,Top" 
                $mSearchOutText.Hide()
       $mSearchOutText.Size = New-Object System.Drawing.Size(200,28) 
        $MyForm.Controls.Add($mSearchOutText)
         
 
        $mSqlServer = New-Object System.Windows.Forms.Label 
                $mSqlServer.Text="SQL Server"
                $mSqlServer.Top="130" 
                $mSqlServer.Left="25" 
                $mSqlServer.Anchor="Left,Top" 
                $mSqlServer.Hide()
        $mSqlServer.Size = New-Object System.Drawing.Size(100,28) 
        $MyForm.Controls.Add($mSqlServer) 
         
 
        $mSQLS = New-Object System.Windows.Forms.TextBox 
                $mSQLS.Text=$env:computername  
                $mSQLS.Top="130" 
                $mSQLS.Left="160" 
                $mSQLS.Anchor="Left,Top" 
                $msqls.Hide()
        $mSQLS.Size = New-Object System.Drawing.Size(200,28) 
        $MyForm.Controls.Add($mSQLS) 
         
 
        $mBrowse_up = New-Object System.Windows.Forms.Button 
                $mBrowse_up.Text="Browse" 
                $mBrowse_up.Top="100" 
                $mBrowse_up.Left="390" 
                $mBrowse_up.Anchor="Left,Top" 
                $mBrowse_up.Hide()
        $mBrowse_up.Size = New-Object System.Drawing.Size(100,28) 
        $MyForm.Controls.Add($mBrowse_up) 
         
 
        $mUpload = New-Object System.Windows.Forms.Button 
                $mUpload.Text="Upload" 
                $mUpload.Top="175" 
                $mUpload.Left="25" 
                $mUpload.Anchor="Left,Top" 
                $mUpload.Hide()
        $mUpload.Size = New-Object System.Drawing.Size(100,28) 
        $MyForm.Controls.Add($mUpload) 
         
  
        $mHTMLPath = New-Object System.Windows.Forms.Label 
                $mHTMLPath.Text="HTML Path" 
                $mHTMLPath.Top="140" 
                $mHTMLPath.Left="25" 
                $mHTMLPath.Anchor="Left,Top" 
                $mHTMLPath.Hide()
        $mHTMLPath.Size = New-Object System.Drawing.Size(100,28) 
        $MyForm.Controls.Add($mHTMLPath) 
         
 
        $mHTML = New-Object System.Windows.Forms.TextBox 
                $FileName = 'Dtrace-'+(Get-Date).tostring("yyyyMMddhhmm")+'.html'
                $mHTML.Text="C:\TEMP\"+$FileName
                $mHTML.Top="140" 
                $mHTML.Left="160" 
                $mHTML.Anchor="Left,Top" 
                $mHTML.Hide()
        $mHTML.Size = New-Object System.Drawing.Size(200,28) 
        $MyForm.Controls.Add($mHTML) 
         
 
       $mBrowse_analyse = New-Object System.Windows.Forms.Button 
                $mBrowse_analyse.Text="Browse" 
                $mBrowse_analyse.Top="140" 
                $mBrowse_analyse.Left="390" 
                $mBrowse_analyse.Anchor="Left,Top" 
                $mBrowse_analyse.Hide()
       $mBrowse_analyse.Size = New-Object System.Drawing.Size(100,28) 
       $MyForm.Controls.Add($mBrowse_analyse) 

       $mBrowse_Extract = New-Object System.Windows.Forms.Button 
                $mBrowse_Extract.Text="Browse" 
                $mBrowse_Extract.Top="175" 
                $mBrowse_Extract.Left="390" 
                $mBrowse_Extract.Anchor="Left,Top" 
                $mBrowse_Extract.Hide()
       $mBrowse_Extract.Size = New-Object System.Drawing.Size(100,28) 
       $MyForm.Controls.Add($mBrowse_Extract) 
  
         $mBrowse_search = New-Object System.Windows.Forms.Button 
                $mBrowse_search.Text="Browse" 
                $mBrowse_search.Top="175" 
                $mBrowse_search.Left="390" 
                $mBrowse_search.Anchor="Left,Top" 
                $mBrowse_search.Hide()
       $mBrowse_search.Size = New-Object System.Drawing.Size(100,28) 
       $MyForm.Controls.Add($mBrowse_search) 
                
 
       $mAnalyse = New-Object System.Windows.Forms.Button 
                $mAnalyse.Text="Analyse" 
                $mAnalyse.Top="260" 
                $mAnalyse.Left="25" 
                $mAnalyse.Anchor="Left,Top"
                $mAnalyse.Hide()
       $mAnalyse.Size = New-Object System.Drawing.Size(100,28) 
       $MyForm.Controls.Add($mAnalyse)


       $mExtractBT = New-Object System.Windows.Forms.Button 
                $mExtractBT.Text="Extract" 
                $mExtractBT.Top="260" 
                $mExtractBT.Left="25" 
                $mExtractBT.Anchor="Left,Top"
                $mExtractBT.Hide()
       $mExtractBT.Size = New-Object System.Drawing.Size(100,28) 
       $MyForm.Controls.Add($mExtractBT)


       $mSearchBT = New-Object System.Windows.Forms.Button 
                $mSearchBT.Text="Search" 
                $mSearchBT.Top="260" 
                $mSearchBT.Left="25" 
                $mSearchBT.Anchor="Left,Top"
                $mSearchBT.Hide()
       $mSearchBT.Size = New-Object System.Drawing.Size(100,28) 
       $MyForm.Controls.Add($mSearchBT)


        $mRUpload = New-Object System.Windows.Forms.RadioButton 
                $mRUpload.Text="Upload Traces" 
                $mRUpload.Top="30" 
                $mRUpload.Left="25" 
                $mRUpload.Anchor="Left,Top"
                $mRUpload.Checked=$true 
        $mRUpload.Size = New-Object System.Drawing.Size(150,28) 
        $MyForm.Controls.Add($mRUpload) 
         
 
        $mRAnalyse = New-Object System.Windows.Forms.RadioButton 
                $mRAnalyse.Text="Analyse Traces" 
                $mRAnalyse.Top="30" 
                $mRAnalyse.Left="175" 
                $mRAnalyse.Anchor="Left,Top" 
        $mRAnalyse.Size = New-Object System.Drawing.Size(150,28) 
        $MyForm.Controls.Add($mRAnalyse) 

        $mRDelayFinder = New-Object System.Windows.Forms.RadioButton 
                $mRDelayFinder.Text="Find Delay" 
                $mRDelayFinder.Top="70" 
                $mRDelayFinder.Left="25" 
                $mRDelayFinder.Anchor="Left,Top" 
        $mRDelayFinder.Size = New-Object System.Drawing.Size(100,28) 
        $MyForm.Controls.Add($mRDelayFinder) 

        $mREventFinder = New-Object System.Windows.Forms.RadioButton 
                $mREventFinder.Text="All Events" 
                $mREventFinder.Top="70" 
                $mREventFinder.Left="150" 
                $mREventFinder.Anchor="Left,Top" 
        $mREventFinder.Size = New-Object System.Drawing.Size(100,28) 
        #$MyForm.Controls.Add($mREventFinder) #Removing, may add in future version. 

        $mRExtractThread = New-Object System.Windows.Forms.RadioButton 
                $mRExtractThread.Text="Extract Thread" 
                $mRExtractThread.Top="70" 
                $mRExtractThread.Left="310" 
                $mRExtractThread.Anchor="Left,Top" 
        $mRExtractThread.Size = New-Object System.Drawing.Size(150,28) 
        $MyForm.Controls.Add($mRExtractThread) 

        $mRSearchException = New-Object System.Windows.Forms.RadioButton 
                $mRSearchException.Text="Search Exception" 
                $mRSearchException.Top="70" 
                $mRSearchException.Left="150" #New position as event option is disabled
                $mRSearchException.Anchor="Left,Top"
        $mRSearchException.Size = New-Object System.Drawing.Size(150,28) 
        $MyForm.Controls.Add($mRSearchException) 

        $mGRPanalyse = New-Object System.Windows.Forms.GroupBox
        $mGRPanalyse.Location = New-Object System.Drawing.Point(10,10)
        $mGRPanalyse.Width="500"
        
        $mGRPanalyse.Height="100"
        
        $MyForm.Controls.Add($mGRPanalyse)
        $mGRPanalyse.Controls.Add($mRDelayFinder)
     #   $mGRPanalyse.Controls.Add($mREventFinder) #Removing, may add in next version
        $mGRPanalyse.Controls.Add($mRExtractThread)
        $mGRPanalyse.Controls.Add($mRSearchException)
        
    
        $R_Upload_click=
        {
            $mDtraceFolder.Show()
            $mDtPath.Show()
            $mBrowse_up.Show()
            $mUpload.Show()
            $mSqlServer.Top="130"
            $mSQLS.Top="130"
            $mSqlServer.Show()
            $mSQLS.Show()
            $mGRPanalyse.Hide()
            $ThreadID.Hide()
            $mThreadIDText.Hide()
            $sThreadOut.Hide()
            $mThreadOutText.Hide()
            $mExtractBT.Hide()
            $mBrowse_Extract.Hide()
            $mHTMLPath.Hide()
            $mBrowse_analyse.Hide()
            $mAnalyse.Hide()
            $mHTML.Hide()
            $mSearchKeyword.Hide()
            $mKeyWordText.Hide()
            $mSearchBT.Hide()
            $mSearchOutText.Hide()
            $mBrowse_search.Hide()
        }
        
        $R_analyse_click=
        {
        
            $mDtraceFoldeR.Hide()
            $mDtPath.Hide()
            $mBrowse_up.Hide()
            $mUpload.Hide()
            $mSqlServer.Hide()
            $mSQLS.Hide()
            $mGRPanalyse.Show()

        }


        $mRDelayFinder_click =
        {
            $mHTMLPath.Show()
            $mBrowse_analyse.Show()
            $mAnalyse.Show()
            $mHTML.Show()
            $mSqlServer.Top="175"
            $mSQLS.Top="175"
            $mSqlServer.Show()
            $mSQLS.Show()
            $ThreadID.Hide()
            $mThreadIDText.Hide()
            $sThreadOut.Hide()
            $mThreadOutText.Hide()
            $mExtractBT.Hide()
            $mBrowse_Extract.Hide()
            $mSearchKeyword.Hide()
            $mKeyWordText.Hide()
            $mSearchBT.Hide()
            $mSearchOutText.Hide()
            $mBrowse_search.Hide()

        }

        $mRExtractThread_click=
        {
            $mHTMLPath.Hide()
            $mBrowse_analyse.Hide()
            $mAnalyse.Hide()
            $mHTML.Hide()
            $mSqlServer.Top="210"
            $mSQLS.Top="210"
            $mSqlServer.Show()
            $mSQLS.Show()
            $ThreadID.Show()
            $mThreadIDText.Show()
            $sThreadOut.Show()
            $mThreadOutText.Show()
            $mExtractBT.Show()
            $mBrowse_Extract.Show()
            $mSearchKeyword.Hide()
            $mKeyWordText.Hide()
            $mSearchBT.Hide()
            $mSearchOutText.Hide()
            $mBrowse_search.Hide()
        }

        $mREventFinder_click=
        {
            $ThreadID.Hide()
            $mThreadIDText.Hide()
            $sThreadOut.Hide()
            $mThreadOutText.Hide()
            $mExtractBT.Hide()
            $mBrowse_Extract.Hide()
            $mHTMLPath.Hide()
            $mBrowse_analyse.Hide()
            $mAnalyse.Hide()
            $mHTML.Hide()
            $mSearchKeyword.Hide()
            $mKeyWordText.Hide()
            $mSearchBT.Hide()
            $mSearchOutText.Hide()
            $mBrowse_search.Hide()
            $mSqlServer.Hide()
            $mSQLS.Hide()
        }

        $mRSearchException_click=

        {
            $ThreadID.Hide()
            $mThreadIDText.Hide()
            $sThreadOut.Hide()
            $mThreadOutText.Hide()
            $mExtractBT.Hide()
            $mBrowse_Extract.Hide()
            $mHTMLPath.Hide()
            $mBrowse_analyse.Hide()
            $mAnalyse.Hide()
            $mHTML.Hide()
            $mSqlServer.Top="210"
            $mSQLS.Top="210"
            $mSqlServer.Show()
            $mSQLS.Show()
            $mSearchKeyword.show()
            $mKeyWordText.show()
            $sThreadOut.Show()
            $mSearchOutText.Show()
            $mSearchBT.Show()
            $mBrowse_search.Show()
        }

        $Browse_Up_BT_Click =  
        { 
            $folder1 = $app.BrowseForFolder(0,"Select folder location of Dtrace Files to scan",0x11)
            $fldr1 = $folder1.Self.Path
            $mDtPath.Text=$fldr1
        }

           
        $mBrowse_analyse_BT_Click =  
        { 
            $folder2 = $app.BrowseForFolder(0,"Select HTML File Location",0x11)
            $fldr2 = $folder2.Self.Path
            $mHTML.Text=$fldr2+'\'+$FileName
            
         } 

         $mBrowse_Extract_BT_click=
         {
            $folder3 = $app.BrowseForFolder(0,"Select Extracted Thread File Location",0x11)
            $fldr3 = $folder3.Self.Path
            $mThreadOutText.Text=$fldr3+'\Dtrace_Thread_'+$mThreadIDText.Text +'.txt'
            
         }

         $mBrowse_Search_BT_click=
         {
            $folder4 = $app.BrowseForFolder(0,"Select File Location for Search Output",0x11)
            $fldr4 = $folder4.Self.Path
            $mSearchOutText.Text=$fldr4+'\'+'SearchResult'+(Get-Date).tostring("yyyyMMddhhmm")+'.txt'
            
         }

        $mUpload_BT_Click=
         {
            $mSQLSrv1=$mSQLS.Text
            $mPth=$mDtPath.Text
            $mUpload.Text="Uploading ..."        
            $MyForm.Enabled=$false            
            UploadDtrace -SQLServer $mSQLSrv1 -DtracePath $mPth -Verbose
            $MyForm.Enabled=$true
            $mUpload.Text="Upload Again"
          }


        $mAnalyseBT_Click=
         {              
             $mSQLSrv2=$mSQLS.Text
             $htmPth=$mHTML.Text 
             $mAnalyse.Text="Analysing ..."
             $MyForm.Enabled=$false        
             DtraceReview -SQLServer $mSQLSrv2 -OutFile $htmPth -Verbose
             $MyForm.Enabled=$true
             $mAnalyse.Text="Analyse"
         }  


         $mExtractBT_click=
         {

             $ThreadID=$mThreadIDText.Text
             $ThreadPath=$mThreadOutText.Text
             $mSQLSrv3=$mSQLS.Text
             $MyForm.Enabled=$false
             OutThread -ThreadId $ThreadID -ThreadPath $ThreadPath -SQLServer $mSQLSrv3 -Verbose 
             $MyForm.Enabled=$true
         
         }

         $mSearchBT_click=
         {
             $SearchTextVar=$mKeyWordText.Text
             $SearchTextVar=$SearchTextVar
             $mSQLSrv4=$mSQLS.Text
             $SearchTextPathVar=$mSearchOutText.Text
             $MyForm.Enabled=$false
             SearchText -SearchText $SearchTextVar  -SearchOutPath $SearchTextPathVar -Verbose -SQLServer $mSQLSrv4
             $MyForm.Enabled=$true
         }

        $mRUpload.add_click($R_Upload_click)
        $mRAnalyse.add_click($R_analyse_click)
        $mBrowse_up.add_click($Browse_Up_bT_Click)
        $mBrowse_analyse.add_click($mBrowse_analyse_BT_Click)
        $mUpload.add_click($mUpload_BT_Click)
        $mAnalyse.add_click($mAnalyseBT_Click)
        $mBrowse_Extract.add_click($mBrowse_Extract_BT_click)
        $mBrowse_search.add_click($mBrowse_Search_BT_click)
        $mExtractBt.add_click($mExtractBT_click)
        $mSearchBT.add_click($mSearchBT_click)
        $mRDelayFinder.add_click($mRDelayFinder_click)
        $mRExtractThread.add_click($mRExtractThread_click)
        # $mREventFinder.add_click($mREventFinder_click) ##Removing, can be added in future version. 
        $mRSearchException.add_click($mRSearchException_click)
                      
        $MyForm.ShowDialog()      
 
