class Case
{
	#Case number WINEP - #####
	$number
	
	#Short description
	$description
	
	#Concat all case info from notes
	$caseLog
	
	#Current week count
	$weekCount
	
	#Maps [W#] -> [#W] Week number to number of weeks worked on.
	$workLog
	
	#End state of case
	$result
	
	
	#Create new case from first note
	Case($num, $desc, $initCaseLog, $initWeek, $resolve)
	{
		"CONSTRUCTOR"
		$this.number = $num
		$num
		$this.description = $desc
		$desc
		$this.caseLog = "<b>W" + $initWeek + ":</b> " + $initCaseLog
		
		$this.weekCount = 1
		
		#On creation 0 weeks of work have been done the week before. This allows all cases to be a line on the graph rather than a single point.
		$this.workLog = @{}
		$this.workLog["W$($initWeek - 1)"] = 0
		$this.workLog["W$initWeek"] = $this.weekCount
		
		$this.result = $resolve
	}
	
	#Append log to existing case and update worklog
	Add($newCaseLog, $week, $resolve)
	{
		$this.caseLog = $this.caseLog + "<br><br><b>W" + $week + ":</b> " + $newCaseLog
		$this.weekCount += 1
		$this.workLog["W$week"] = $this.weekCount
		
		#Prevent overwrite of result in case of update after result tag in note.
		if ($this.result -eq "Unresolved")
		{
			$this.result = $resolve;
		}
	}
}

#TODO: column role style can set colour, allow colour to be persisited through filter by using case number somehow (hash?)

Function toHTML($cases_map)
{
	#$data is a javascript string that will be added to the base html file
	#it contains the dataTable for the charts api
	$data = "data.addColumn({type:'string', role:'domain', label:'Week'});"
	
	#The graph legend is in addition order, so sort here to ensure they are sensibly ordered.
	$sortedEnum = $($cases_map.GetEnumerator() | sort -Property name)
	
	#Add a column to the data table for each case. Each case also has a tooltip column with label '[Case#]T'.
	foreach( $k in $sortedEnum.Name)
	{
		$data = $data + "`ndata.addColumn({type:'number', role:'data', label:'" + $k + "'});`ndata.addColumn({type:'string', role:'tooltip', label:'" + $k + "T'});"
	}
	
	#i starts at 0 for cases that begin in W1
	$i = 0
	
	#Each row is a week. A Cell corresponds to a case and a week, and denotes how many weeks of work have been done on the case.
	#Nulls are currently interpolated, might fill out to give flat sections later
	$data = $data + "`n" + "data. addRows(["
	do
	{
		#First column is week number
		$data = $data + "`n['$i'"
		
		foreach($case in $sortedEnum)
		{	
			$val = $case.value.workLog["W$i"]
			
			if ($val -eq $null) {
				#Value must be null string not actually null as it will be run as JS
				$val = "null"
				$tooltip = "''"
			}
			else
			{
				#tooltip shows on hover over the graph line
				$tooltip = "'" + $case.value.number + ": " + $case.value.description + "'"
			}
			#add two cells to the current row - the data then the tooltip for the current case.
			$data = $data + "," + $val + "," + $tooltip
		}
		#Close data row
		$data = $data + "],"
		$i++
	}
	while($i -lt 52)
	$data = $data + "]);"
	
	#Initially I had this in the loop above then realised I didn't need to do it 52 times :/
	
	#CaseInfo is extra data not contained in the graph - the CaseLog and result mapped by caseNumber
	$addCaseInfo = ""
	foreach($case in $sortedEnum)
	{	
		
		#Create CaseInfo item, Case number maps to a list containing Description (tooltip), CaseLog String as HTML and result.
		$addCaseInfo = $addCaseInfo + "CaseInfo['" + $case.value.number + "'] = ['" + $case.value.description + "','" + $case.value.caseLog + "','" + $case.value.result+ "']`n"
	}
	
	#Read base HTML file
	$pwd = Get-Location
	$base = [IO.File]::ReadAllText("$pwd\ParseNotesBase.html") 

	#Replace variables
	$page = $base.replace('$addCaseInfo', $addCaseInfo).replace('$str',$data)
	
	#Write Out as UTF8 to prevent powershell wide chars
	$page | Out-File CasesGraph.html -Encoding UTF8
	Invoke-Item CasesGraph.html #open html file with default reader (browser).
}

Function main
{
	#Map [Case Number] -> [Case Object]
	$cases_map = @{} 

	$pwd = Get-Location
	
	#Get files from Keep only where they are a Case log. Could have parse the file for the tag but this is quicker than opening and reading them all
	$files = (Get-ChildItem "$pwd\Keep\" | Where-Object {$_.Name -match "W.*"}).Name -replace "W([0-9]) ", "W0`$1 "
	
	#Sort to get caseLogs in chronological order. Above W[1-9] is replaced by W0[1-9] to allow sorting
	$files = $files | Sort-Object
	#Get all files sorted and excluding non related files
	
	foreach ($file in $files)
	{	
		
		$file = $file -replace "W0([0-9]) ", "W`$1 " #swap back
		
		$URI = "file:\\\$pwd\Keep\$file"
		$HTML = Invoke-WebRequest $URI
		#parse as HTML
		
		$f = $file -match 'W([0-9]+) '
		if ($f)
		{
			#Get Week number
			$week = $matches[1]
		}
		
		#Get Content tag text from html
		$found = $HTML.RawContent -match '<div class="content">(.*?)</div>'
		
		if ($found)
		{
			$content = $matches[1]
			$s_content = $content -split "(<br>)+? *- " #Split case notes on line breaks and hyphen bullet points
			
			foreach ($case in $s_content)
			{
				
				if ($case -eq "<br>") { continue } #Skip delimiters
				$f2 = $case -match '(?: - )*([0-9]+) \*(.*?)\* (.*)' #Brackets return to matches variable in case you forgot. (?: ...) groups but doesn't return.
				#Match Case number, description in * * and contents
				
				if ($f2)
				{				
					$CaseNum = $matches[1]
					$CaseDesc = $matches[2]
					$CaseLog = $matches[3]
					
					if($CaseLog -match '###(.*?)###') #Get result tag if it exisits
					{
						$result = $matches[1]
						$CaseLog = $CaseLog -replace '###(.*?)###','' #Remove tag from CaseLog
					}
					else
					{
						$result = "Unresolved"
					}
					if ($cases_map[$CaseNum] -eq $null)
					{
						#Create object if doesn't exist
						$cases_map[$CaseNum] = New-Object -TypeName Case -ArgumentList $CaseNum,$CaseDesc,$CaseLog,$week,$result
					}
					else
					{
						#Add to existing object
						$cases_map[$CaseNum].add($CaseLog,$week,$result)
					}
				}
			}
		}		
	}
	toHTML($cases_map)
}

main