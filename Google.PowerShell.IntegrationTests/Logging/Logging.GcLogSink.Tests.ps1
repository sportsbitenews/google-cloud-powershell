﻿. $PSScriptRoot\..\GcloudCmdlets.ps1
Install-GCloudCmdlets

$project, $zone, $oldActiveConfig, $configName = Set-GCloudConfig
# Default service account used by cloud logs if -UniqueWriterIdentity is not used.
$script:cloudLogServiceAccount = "serviceAccount:cloud-logs@system.gserviceaccount.com"
# Cloud-logs already has permission to write to this topic.
$script:pubsubTopicWithPermission = "gcloud-powershell-exported-log"

Describe "Get-GcLogSink" {
    $r = Get-Random
    $script:sinkName = "gcps-get-gclogsink-$r"
    $script:secondSinkName = "gcps-get-gclogsink2-$r"
    $script:bucketOne = "random-destination-will-do-$r"
    $script:bucketTwo = "random-destination-will-do2-$r"
    $destination = "storage.googleapis.com/$bucketOne"
    $destinationTwo = "storage.googleapis.com/$bucketTwo"
    $logFilter = "this is a filter"
    
    # We have to create the buckets before creating the log sink.
    New-GcsBucket $bucketOne
    New-GcsBucket $bucketTwo
    Start-Sleep 2
    gcloud beta logging sinks create $script:sinkName $destination --log-filter=$logFilter --quiet 2>$null
    gcloud beta logging sinks create $script:secondSinkName $destinationTwo --quiet 2>$null
    
    AfterAll {
        Remove-GcsBucket $bucketOne -Force
        Remove-GcsBucket $bucketTwo -Force
        gcloud beta logging sinks delete $sinkName --quiet 2>$null
        gcloud beta logging sinks delete $secondSinkName --quiet 2>$null
    }

    It "should work without any parameters" {
        $sinks = Get-GcLogSink

        $firstSink = $sinks | Where-Object {$_.Name -eq $sinkName}
        $firstSink | Should Not BeNullOrEmpty
        $firstSink.Destination | Should BeExactly $destination
        $firstSink.OutputVersionFormat | Should BeExactly V2
        $firstSink.Filter | Should BeExactly $logFilter
        $firstSink.WriterIdentity | Should Not BeNullOrEmpty

        $secondSink = $sinks | Where-Object {$_.Name -eq $secondSinkName}
        $secondSink | Should Not BeNullOrEmpty
        $secondSink.Destination | Should BeExactly $destinationTwo
        $secondSink.OutputVersionFormat | Should BeExactly V2
        $secondSink.Filter | Should BeNullOrEmpty
        $secondSink.WriterIdentity | Should Not BeNullOrEmpty
    }

    It "should work with -Sink parameter" {
        $firstSink = Get-GcLogSink -Sink $sinkName
        $firstSink | Should Not BeNullOrEmpty
        $firstSink.Name | Should BeExactly "$sinkName"
        $firstSink.Destination | Should BeExactly $destination
        $firstSink.OutputVersionFormat | Should BeExactly V2
        $firstSink.Filter | Should BeExactly $logFilter
        $firstSink.WriterIdentity | Should Not BeNullOrEmpty
    }

    It "should work with an array of sinks names" {
        $sinks = Get-GcLogSink -Sink $sinkName, $secondSinkName
        $sinks.Count | Should Be 2

        $firstSink = $sinks | Where-Object {$_.Name -eq $sinkName}
        $firstSink | Should Not BeNullOrEmpty
        $firstSink.Destination | Should BeExactly $destination
        $firstSink.OutputVersionFormat | Should BeExactly V2
        $firstSink.Filter | Should BeExactly $logFilter
        $firstSink.WriterIdentity | Should Not BeNullOrEmpty

        $secondSink = $sinks | Where-Object {$_.Name -eq $secondSinkName}
        $secondSink | Should Not BeNullOrEmpty
        $secondSink.Destination | Should BeExactly $destinationTwo
        $secondSink.OutputVersionFormat | Should BeExactly V2
        $secondSink.Filter | Should BeNullOrEmpty
        $secondSink.WriterIdentity | Should Not BeNullOrEmpty    }

    It "should throw an error for non-existent sink" {
        { Get-GcLogSink -Sink "non-existent-sink-name" -ErrorAction Stop } | Should Throw "does not exist"
    }
}

Describe "New-GcLogSink" {
    function Test-GcLogSink (
        [string]$name,
        [string]$destination,
        [string]$outputVersionFormat,
        [string]$writerIdentity,
        [DateTime]$startTime,
        [DateTime]$endTime,
        [Google.Apis.Logging.v2.Data.LogSink]$sink)
    {
        $sink | Should Not BeNullOrEmpty
        $sink.Name | Should BeExactly $name
        $sink.Destination | Should BeExactly $destination
        $sink.OutputVersionFormat | Should BeExactly $outputVersionFormat
        $sink.WriterIdentity | Should Not BeNullOrEmpty

        # Only checks for writer identity if it is provided.
        if (-not [string]::IsNullOrWhiteSpace($writerIdentity)) {
            $sink.WriterIdentity | Should BeExactly $writerIdentity
        }

        if ($null -eq $startTime) {
            $sink.StartTime | Should BeNullOrEmpty
        }
        else {
            [DateTime]$sink.StartTime | Should Be $startTime
        }

        if ($null -eq $endTime) {
            $sink.EndTime | Should BeNullOrEmpty
        }
        else {
            [DateTime]$sink.EndTime | Should Be $endTime
        }
    }

    It "should work with -GcsBucketDestination" {
        $r = Get-Random
        $bucket = "gcloud-powershell-testing-logsink-bucket-$r"
        $sinkName = "gcps-new-gclogsink-$r"
        try {
            New-GcsBucket $bucket
            Start-Sleep -Seconds 1

            New-GcLogSink $sinkName -GcsBucketDestination $bucket -UniqueWriterIdentity
            Start-Sleep -Seconds 1

            $createdSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "storage.googleapis.com/$bucket" `
                           -OutputVersionFormat "V2" `
                           -Sink $createdSink
        }
        finally {
            Remove-GcsBucket $bucket -Force
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
        }
    }

    It "should work with -BigQueryDataSetDestination" {
        $r = Get-Random
        $dataset = "gcloud_powershell_testing_dataset_$r"
        $sinkName = "gcps-new-gclogsink-$r"
        try {
            New-GcLogSink $sinkName -BigQueryDataSetDestination $dataset
            Start-Sleep -Seconds 1

            $createdSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "bigquery.googleapis.com/projects/$project/datasets/$dataset" `
                           -OutputVersionFormat "V2" `
                           -Sink $createdSink `
                           -WriterIdentity $script:cloudLogServiceAccount
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
        }
    }

    It "should work with -PubSubTopicDestination" {
        $r = Get-Random
        $pubsubTopic = "gcloud-powershell-testing-pubsubtopic-$r"
        $sinkName = "gcps-new-gclogsink-$r"
        try {
            New-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopic
            Start-Sleep -Seconds 1

            $createdSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopic" `
                           -OutputVersionFormat "V2" `
                           -Sink $createdSink `
                           -WriterIdentity $script:cloudLogServiceAccount
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
        }
    }

    It "should work with -UniqueWriterIdentity" {
        $r = Get-Random
        $pubsubTopic = "gcloud-powershell-testing-pubsubtopic-$r"
        $sinkName = "gcps-new-gclogsink-$r"
        $sinkNameTwo = "gcps-new-gclogsink2-$r"
        try {
            New-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopic
            New-GcLogSink $sinkNameTwo -PubSubTopicDestination $pubsubTopic -UniqueWriterIdentity
            Start-Sleep -Seconds 1

            $createdSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopic" `
                           -OutputVersionFormat "V2" `
                           -WriterIdentity $script:cloudLogServiceAccount `
                           -Sink $createdSink

            $createdSink = Get-GcLogSink -Sink $sinkNameTwo
            $createdSink.WriterIdentity | Should Not Be $script:cloudLogServiceAccount
            Test-GcLogSink -Name $sinkNameTwo `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopic" `
                           -OutputVersionFormat "V2" `
                           -Sink $createdSink
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
            gcloud beta logging sinks delete $sinkNameTwo --quiet 2>$null
        }
    }


    It "should work with -Before and -After" {
        $r = Get-Random
        $pubsubTopic = "gcloud-powershell-pubsub-topic-testing-$r"
        $sinkName = "gcps-new-gclogsink-$r"
        $secondSinkName = "gcps-new-gclogsink2-$r"
        $thirdSinkName = "gcps-new-gclogsink3-$r"
        $logName = "gcps-new-gclogsink-log-$r"
        try {
            $firstTime = ([DateTime]::Now).AddMinutes(4)
            $secondTime = $firstTime.AddMinutes(4)
            New-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopic -Before $firstTime
            New-GcLogSink $secondSinkName -PubSubTopicDestination $pubsubTopic -After $secondTime
            New-GcLogSink $thirdSinkName -PubSubTopicDestination $pubsubTopic -Before $secondTime -After $firstTime
            Start-Sleep -Seconds 1

            $createdSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopic" `
                           -OutputVersionFormat "V2" `
                           -EndTime $firstTime `
                           -Sink $createdSink

            $createdSink = Get-GcLogSink -Sink $secondSinkName
            Test-GcLogSink -Name $secondSinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopic" `
                           -OutputVersionFormat "V2" `
                           -StartTime $secondTime `
                           -Sink $createdSink

            $createdSink = Get-GcLogSink -Sink $thirdSinkName
            Test-GcLogSink -Name $thirdSinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopic" `
                           -OutputVersionFormat "V2" `
                           -StartTime $firstTime `
                           -EndTime $secondTime `
                           -Sink $createdSink
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
            gcloud beta logging sinks delete $secondSinkName --quiet 2>$null
            gcloud beta logging sinks delete $thirdSinkName --quiet 2>$null
        }
    }

    It "should work with -LogName" {
        $r = Get-Random
        $sinkName = "gcps-new-gclogsink-$r"
        $logName = "gcps-new-gclogsink-log-$r"
        $secondLogName = "gcps-new-gclogsink-log2-$r"
        $subscriptionName = "gcps-new-gclogsink-subscription-$r"
        $textPayload = "This is a message with $r."
        try {
            New-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopicWithPermission -LogName $logName
            New-GcpsSubscription -Subscription $subscriptionName -Topic $pubsubTopicWithPermission
            # We need to sleep before creating the log entry to account for the time the logsink
            # and the subscription is created.
            Start-Sleep -Seconds 20

            $createdSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopicWithPermission" `
                           -WriterIdentity $script:cloudLogServiceAccount `
                           -OutputVersionFormat "V2" `
                           -Sink $createdSink

            # Write a log entry to the log, we should be able to get it from the subscription since it will be exported to the topic.
            New-GcLogEntry -LogName $logName -TextPayload $textPayload
            # Write a different entry to a different log (we should not get this).
            New-GcLogEntry -LogName $secondLogName -TextPayload "You should not get this."
            # We need to sleep before getting the message to account for the delay before the log is exported to the topic.
            Start-Sleep -Seconds 20

            $message = Get-GcpsMessage -Subscription $subscriptionName -AutoAck
            $messageJson = ConvertFrom-Json $message.Data
            $messageJson.LogName | Should Match $logName
            $messageJson.TextPayload | Should BeExactly $textPayload
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
            Remove-GcpsSubscription -Subscription $subscriptionName -ErrorAction SilentlyContinue
            Remove-GcLog $logName -ErrorAction SilentlyContinue
            Remove-GcLog $secondLogName -ErrorAction SilentlyContinue
        }
    }

    It "should work with -Filter" {
        $r = Get-Random
        $sinkName = "gcps-new-gclogsink-$r"
        $logName = "gcps-new-gclogsink-log-$r"
        $subscriptionName = "gcps-new-gclogsink-subscription-$r"
        $textPayload = "This is a message with $r."
        $secondTextPayload = "This is the second text payload with $r."
        $filter = "textPayload=`"$secondTextPayload`""
        try {
            New-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopicWithPermission -LogName $logName -Filter $filter
            New-GcpsSubscription -Subscription $subscriptionName -Topic $pubsubTopicWithPermission
            # We need to sleep before creating the log entry to account for the time the logsink
            # and the subscription is created.
            Start-Sleep -Seconds 20

            $createdSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopicWithPermission" `
                           -WriterIdentity $script:cloudLogServiceAccount `
                           -OutputVersionFormat "V2" `
                           -Sink $createdSink

            New-GcLogEntry -LogName $logName -TextPayload $textPayload
            New-GcLogEntry -LogName $logName -TextPayload $secondTextPayload
            # We need to sleep before getting the message to account for the delay before the log is exported to the topic.
            Start-Sleep -Seconds 20

            $message = Get-GcpsMessage -Subscription $subscriptionName -AutoAck
            $messageJson = ConvertFrom-Json $message.Data
            $messageJson.LogName | Should Match $logName
            $messageJson.TextPayload | Should BeExactly $secondTextPayload
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
            Remove-GcpsSubscription -Subscription $subscriptionName -ErrorAction SilentlyContinue
            Remove-GcLog $logName -ErrorAction SilentlyContinue
        }
    }

    It "should work with -Severity" {
        $r = Get-Random
        $sinkName = "gcps-new-gclogsink-$r"
        $logName = "gcps-new-gclogsink-log-$r"
        $subscriptionName = "gcps-new-gclogsink-subscription-$r"
        $debugPayload = "This is a message with severity debug."
        $infoPayload = "This is a message with severity info."
        $errorPayload = "This is a message with severity error."
        try {
            New-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopicWithPermission -LogName $logName -Severity Error
            New-GcpsSubscription -Subscription $subscriptionName -Topic $pubsubTopicWithPermission
            # We need to sleep before creating the log entry to account for the time the logsink
            # and the subscription is created.
            Start-Sleep -Seconds 20

            $createdSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopicWithPermission" `
                           -WriterIdentity $script:cloudLogServiceAccount `
                           -OutputVersionFormat "V2" `
                           -Sink $createdSink

            New-GcLogEntry -LogName $logName -TextPayload $debugPayload -Severity Debug
            New-GcLogEntry -LogName $logName -TextPayload $infoPayload -Severity Info
            New-GcLogEntry -LogName $logName -TextPayload $errorPayload -Severity Error
            # We need to sleep before getting the message to account for the delay before the log is exported to the topic.
            Start-Sleep -Seconds 20

            $message = Get-GcpsMessage -Subscription $subscriptionName -AutoAck
            $messageJson = ConvertFrom-Json $message.Data
            $messageJson.LogName | Should Match $logName
            $messageJson.TextPayload | Should BeExactly $errorPayload
            $messageJson.Severity | Should BeExactly ERROR
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
            Remove-GcpsSubscription -Subscription $subscriptionName -ErrorAction SilentlyContinue
            Remove-GcLog $logName -ErrorAction SilentlyContinue
        }
    }

    It "should throw an error for creating a sink that already exists." {
        $r = Get-Random
        $sinkName = "gcps-new-gclogsink-$r"
        try {
            New-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopicWithPermission -UniqueWriterIdentity
            Start-Sleep -Seconds 1

            $createdSink = Get-GcLogSink -Sink $sinkName
            $createdSink | Should Not BeNullOrEmpty

            { New-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopicWithPermission -ErrorAction Stop }  |
                Should Throw "already exists"
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
        }
    }
}

Describe "Set-GcLogSink" {
    function Test-GcLogSink (
        [string]$name,
        [string]$destination,
        [string]$outputVersionFormat,
        [string]$writerIdentity,
        [DateTime]$startTime,
        [DateTime]$endTime,
        [Google.Apis.Logging.v2.Data.LogSink]$sink)
    {
        $sink | Should Not BeNullOrEmpty
        $sink.Name | Should BeExactly $name
        $sink.Destination | Should BeExactly $destination
        $sink.OutputVersionFormat | Should BeExactly $outputVersionFormat
        $sink.WriterIdentity | Should Not BeNullOrEmpty

        # Only checks for writer identity if it is provided.
        if (-not [string]::IsNullOrWhiteSpace($writerIdentity)) {
            $sink.WriterIdentity | Should BeExactly $writerIdentity
        }

        if ($null -eq $startTime) {
            $sink.StartTime | Should BeNullOrEmpty
        }
        else {
            [DateTime]$sink.StartTime | Should Be $startTime
        }

        if ($null -eq $endTime) {
            $sink.EndTime | Should BeNullOrEmpty
        }
        else {
            [DateTime]$sink.EndTime | Should Be $endTime
        }
    }

    It "should work with -GcsBucketDestination" {
        $r = Get-Random
        $bucket = "gcloud-powershell-testing-logsink-bucket-$r"
        $bucketTwo = "gcloud-powershell-testing-logsink-bucket-2-$r"
        $sinkName = "gcps-new-gclogsink-$r"
        try {
            New-GcsBucket $bucket
            New-GcsBucket $bucketTwo
            Start-Sleep -Seconds 1

            New-GcLogSink $sinkName -GcsBucketDestination $bucket -UniqueWriterIdentity
            Start-Sleep -Seconds 1

            Set-GcLogSink $sinkName -GcsBucketDestination $bucketTwo -UniqueWriterIdentity
            Start-Sleep -Seconds 1

            $updatedSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "storage.googleapis.com/$bucketTwo" `
                           -OutputVersionFormat "V2" `
                           -Sink $updatedSink 
        }
        finally {
            Remove-GcsBucket $bucket -Force
            Remove-GcsBucket $bucketTwo -Force
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
        }
    }

    It "should work with -BigQueryDataSetDestination" {
        $r = Get-Random
        $dataset = "gcloud_powershell_testing_dataset_$r"
        $datasetTwo = "gcloud_powershell_testing_dataset_two_$r"
        $sinkName = "gcps-new-gclogsink-$r"
        try {
            New-GcLogSink $sinkName -BigQueryDataSetDestination $dataset
            Start-Sleep -Seconds 1

            Set-GcLogSink $sinkName -BigQueryDataSetDestination $datasetTwo
            Start-Sleep -Seconds 1

            $updatedSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "bigquery.googleapis.com/projects/$project/datasets/$datasetTwo" `
                           -OutputVersionFormat "V2" `
                           -Sink $updatedSink `
                           -WriterIdentity $script:cloudLogServiceAccount
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
        }
    }

    It "should work with -PubSubTopicDestination" {
        $r = Get-Random
        $pubsubTopic = "gcloud-powershell-testing-pubsubtopic-$r"
        $pubsubTopicTwo = "gcloud-powershell-testing-pubsubtopic-2-$r"
        $sinkName = "gcps-new-gclogsink-$r"
        try {
            New-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopic
            Start-Sleep -Seconds 1

            Set-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopicTwo
            Start-Sleep -Seconds 1

            $updatedSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopicTwo" `
                           -OutputVersionFormat "V2" `
                           -Sink $updatedSink `
                           -WriterIdentity $script:cloudLogServiceAccount
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
        }
    }

    It "should work with -OutputVersionFormat" {
        $r = Get-Random
        $bucket = "gcloud-powershell-testing-pubsubtopic-1-$r"
        $bucketTwo = "gcloud-powershell-testing-pubsubtopic-2-$r"
        $sinkName = "gcps-new-gclogsink-$r"
        $sinkNameTwo = "gcps-new-gclogsink2-$r"
        try {
            New-GcsBucket $bucket
            New-GcsBucket $bucketTwo
            Start-Sleep -Seconds 1

            New-GcLogSink $sinkName -GcsBucketDestination $bucket -UniqueWriterIdentity
            # Have to be a different topic because sinks with diffferent output formats cannot share destination.
            New-GcLogSink $sinkNameTwo -GcsBucketDestination $bucketTwo -UniqueWriterIdentity
            Start-Sleep -Seconds 1

            Set-GcLogSink $sinkName -UniqueWriterIdentity
            Set-GcLogSink $sinkNameTwo -GcsBucketDestination $bucketTwo -UniqueWriterIdentity
            Start-Sleep -Seconds 1

            $updatedSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "storage.googleapis.com/$bucket" `
                           -OutputVersionFormat "V2" `
                           -Sink $updatedSink

            $updatedSink = Get-GcLogSink -Sink $sinkNameTwo
            Test-GcLogSink -Name $sinkNameTwo `
                           -Destination "storage.googleapis.com/$bucketTwo" `
                           -OutputVersionFormat "V2" `
                           -Sink $updatedSink
        }
        finally {
            Remove-GcsBucket $bucket -Force
            Remove-GcsBucket $bucketTwo -Force
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
            gcloud beta logging sinks delete $sinkNameTwo --quiet 2>$null
        }
    }

    It "should work with -UniqueWriterIdentity" {
        $r = Get-Random
        $pubsubTopic = "gcloud-powershell-testing-pubsubtopic-$r"
        $sinkName = "gcps-new-gclogsink-$r"
        try {
            New-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopic
            Start-Sleep -Seconds 1

            Set-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopic -UniqueWriterIdentity
            Start-Sleep -Seconds 1

            $updatedSink = Get-GcLogSink -Sink $sinkName
            $updatedSink.WriterIdentity | Should Not Be $script:cloudLogServiceAccount
            Test-GcLogSink -Name $sinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopic" `
                           -OutputVersionFormat "V2" `
                           -Sink $updatedSink
            
            # Should not change the second time we run it
            Set-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopic -UniqueWriterIdentity
            Start-Sleep -Seconds 1

            $secondUpdatedSink = Get-GcLogSink -Sink $sinkName
            $secondUpdatedSink.WriterIdentity | Should Not Be $script:cloudLogServiceAccount
            Test-GcLogSink -Name $sinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopic" `
                           -OutputVersionFormat "V2" `
                           -WriterIdentity $updatedSink.WriterIdentity `
                           -Sink $secondUpdatedSink
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
        }
    }

    It "should work with -Before and -After" {
        $r = Get-Random
        $pubsubTopic = "gcloud-powershell-pubsub-topic-testing-$r"
        $sinkName = "gcps-new-gclogsink-$r"
        $secondSinkName = "gcps-new-gclogsink2-$r"
        $thirdSinkName = "gcps-new-gclogsink3-$r"
        $logName = "gcps-new-gclogsink-log-$r"
        try {
            $firstTime = ([DateTime]::Now).AddMinutes(4)
            $secondTime = $firstTime.AddMinutes(4)
            New-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopic -Before $firstTime
            New-GcLogSink $secondSinkName -PubSubTopicDestination $pubsubTopic -After $secondTime
            New-GcLogSink $thirdSinkName -PubSubTopicDestination $pubsubTopic -Before $secondTime -After $firstTime
            Start-Sleep -Seconds 1

            $thirdTime = $firstTime.AddMinutes(8)
            $fourthTime = $firstTime.AddMinutes(12)
            Set-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopic -Before $thirdTime
            Set-GcLogSink $secondSinkName -After $fourthTime
            Set-GcLogSink $thirdSinkName -PubSubTopicDestination $pubsubTopic -Before $fourthTime -After $thirdTime
            Start-Sleep -Seconds 1

            $updatedSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopic" `
                           -OutputVersionFormat "V2" `
                           -EndTime $thirdTime `
                           -Sink $updatedSink

            $updatedSink = Get-GcLogSink -Sink $secondSinkName
            Test-GcLogSink -Name $secondSinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopic" `
                           -OutputVersionFormat "V2" `
                           -StartTime $fourthTime `
                           -Sink $updatedSink

            $updatedSink = Get-GcLogSink -Sink $thirdSinkName
            Test-GcLogSink -Name $thirdSinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopic" `
                           -OutputVersionFormat "V2" `
                           -StartTime $thirdTime `
                           -EndTime $fourthTime `
                           -Sink $updatedSink
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
            gcloud beta logging sinks delete $secondSinkName --quiet 2>$null
            gcloud beta logging sinks delete $thirdSinkName --quiet 2>$null
        }
    }

    It "should work with -LogName" {
        $r = Get-Random
        $sinkName = "gcps-new-gclogsink-$r"
        $logName = "gcps-new-gclogsink-log-$r"
        $secondLogName = "gcps-new-gclogsink-log2-$r"
        $subscriptionName = "gcps-new-gclogsink-subscription-$r"
        $textPayload = "This is a message with $r."
        try {
            New-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopicWithPermission -LogName $logName
            New-GcpsSubscription -Subscription $subscriptionName -Topic $pubsubTopicWithPermission
            Start-Sleep -Seconds 2

            # Change the log name filter of the sink.
            Set-GcLogSink $sinkName -LogName $secondLogName
            # We need to sleep before creating the log entry to account for the time the logsink
            # and the subscription is created.
            Start-Sleep -Seconds 20

            # Write a log entry to the log, we should be able to get it from the subscription since it will be exported to the topic.
            New-GcLogEntry -LogName $secondLogName -TextPayload $textPayload
            # Write a different entry to a different log (we should not get this).
            New-GcLogEntry -LogName $logName -TextPayload "You should not get this."
            # We need to sleep before getting the message to account for the delay before the log is exported to the topic.
            Start-Sleep -Seconds 20

            $message = Get-GcpsMessage -Subscription $subscriptionName -AutoAck
            $messageJson = ConvertFrom-Json $message.Data
            $messageJson.LogName | Should Match $secondLogName
            $messageJson.TextPayload | Should BeExactly $textPayload
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
            Remove-GcpsSubscription -Subscription $subscriptionName -ErrorAction SilentlyContinue
            Remove-GcLog $logName -ErrorAction SilentlyContinue
            Remove-GcLog $secondLogName -ErrorAction SilentlyContinue
        }
    }

    It "should work with -Filter" {
        $r = Get-Random
        $sinkName = "gcps-new-gclogsink-$r"
        $logName = "gcps-new-gclogsink-log-$r"
        $subscriptionName = "gcps-new-gclogsink-subscription-$r"
        $textPayload = "This is a message with $r."
        $secondTextPayload = "This is the second text payload with $r."
        $filter = "textPayload=`"$secondTextPayload`""
        $secondFilter = "textPayload=`"$textPayload`""
        try {
            New-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopicWithPermission -LogName $logName -Filter $filter
            New-GcpsSubscription -Subscription $subscriptionName -Topic $pubsubTopicWithPermission
            Start-Sleep -Seconds 2

            # We need to sleep before creating the log entry to account for the time the logsink
            # and the subscription is created.
            Set-GcLogSink $sinkName -LogName $logName -Filter $secondFilter
            Start-Sleep -Seconds 20

            $createdSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopicWithPermission" `
                           -WriterIdentity $script:cloudLogServiceAccount `
                           -OutputVersionFormat "V2" `
                           -Sink $createdSink

            New-GcLogEntry -LogName $logName -TextPayload $textPayload
            New-GcLogEntry -LogName $logName -TextPayload $secondTextPayload
            # We need to sleep before getting the message to account for the delay before the log is exported to the topic.
            Start-Sleep -Seconds 20

            $message = Get-GcpsMessage -Subscription $subscriptionName -AutoAck
            $messageJson = ConvertFrom-Json $message.Data
            $messageJson.LogName | Should Match $logName
            $messageJson.TextPayload | Should BeExactly $textPayload
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
            Remove-GcpsSubscription -Subscription $subscriptionName -ErrorAction SilentlyContinue
            Remove-GcLog $logName -ErrorAction SilentlyContinue
        }
    }

    It "should work with -Severity" {
        $r = Get-Random
        $sinkName = "gcps-new-gclogsink-$r"
        $logName = "gcps-new-gclogsink-log-$r"
        $subscriptionName = "gcps-new-gclogsink-subscription-$r"
        $debugPayload = "This is a message with severity debug."
        $infoPayload = "This is a message with severity info."
        $errorPayload = "This is a message with severity error."
        try {
            New-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopicWithPermission -LogName $logName -Severity Error
            New-GcpsSubscription -Subscription $subscriptionName -Topic $pubsubTopicWithPermission
            Start-Sleep -Seconds 2

            Set-GcLogSink $sinkName -LogName $logName -Severity Info

            # We need to sleep before creating the log entry to account for the time the logsink
            # and the subscription is created.
            Start-Sleep -Seconds 20

            $createdSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopicWithPermission" `
                           -WriterIdentity $script:cloudLogServiceAccount `
                           -OutputVersionFormat "V2" `
                           -Sink $createdSink

            New-GcLogEntry -LogName $logName -TextPayload $debugPayload -Severity Debug
            New-GcLogEntry -LogName $logName -TextPayload $infoPayload -Severity Info
            New-GcLogEntry -LogName $logName -TextPayload $errorPayload -Severity Error
            # We need to sleep before getting the message to account for the delay before the log is exported to the topic.
            Start-Sleep -Seconds 20

            $message = Get-GcpsMessage -Subscription $subscriptionName -AutoAck
            $messageJson = ConvertFrom-Json $message.Data
            $messageJson.LogName | Should Match $logName
            $messageJson.TextPayload | Should BeExactly $infoPayload
            $messageJson.Severity | Should BeExactly INFO
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
            Remove-GcpsSubscription -Subscription $subscriptionName -ErrorAction SilentlyContinue
            Remove-GcLog $logName -ErrorAction SilentlyContinue
        }
    }

    It "should create a sink if the sink does not exist." {
        $r = Get-Random
        $sinkName = "gcps-new-gclogsink-$r"
        try {
            Set-GcLogSink $sinkName -PubSubTopicDestination $pubsubTopicWithPermission
            Start-Sleep -Seconds 1

            $createdSink = Get-GcLogSink -Sink $sinkName
            Test-GcLogSink -Name $sinkName `
                           -Destination "pubsub.googleapis.com/projects/$project/topics/$pubsubTopicWithPermission" `
                           -OutputVersionFormat "V2" `
                           -Sink $createdSink `
                           -WriterIdentity $script:cloudLogServiceAccount
        }
        finally {
            gcloud beta logging sinks delete $sinkName --quiet 2>$null
        }
    }

    It "should error out if sink does not exist and destination is not provided." {
        $r = Get-Random
        $sinkName = "gcps-new-gclogsink-$r"
        { Set-GcLogSink $sinkName } | Should Throw "does not exist"
    }
}

Describe "Remove-GcLogSink" {
    It "should throw error for non-existent log sink" {
        { Remove-GcLogSink -SinkName "non-existent-log-sink-powershell-testing" -ErrorAction Stop } |
            Should Throw "does not exist"
    }

    It "should work" {
        $r = Get-Random
        $bucket = "gcloud-powershell-testing-logsink-bucket-$r"
        $sinkName = "gcps-new-gclogsink-$r"

        New-GcsBucket $bucket
        Start-Sleep -Seconds 1

        New-GcLogSink $sinkName -GcsBucketDestination $bucket -UniqueWriterIdentity
        Start-Sleep -Seconds 1

        try {
            $createdSink = Get-GcLogSink -Sink $sinkName
            $createdSink | Should Not BeNullOrEmpty

            Remove-GcLogSink $sinkName
            { Get-GcLogSink -Sink $sinkName -ErrorAction Stop } | Should Throw "does not exist"
        }
        finally {
            Remove-GcsBucket $bucket -Force
        }
    }


    It "should work for multiple sinks" {
        $r = Get-Random
        $bucket = "gcloud-powershell-testing-logsink-bucket-$r"
        $sinkName = "gcps-new-gclogsink-$r"
        $sinkNameTwo = "gcps-new-gclogsink2-$r"

        New-GcsBucket $bucket
        Start-Sleep -Seconds 1

        New-GcLogSink $sinkName -GcsBucketDestination $bucket -UniqueWriterIdentity
        New-GcLogSink $sinkNameTwo -GcsBucketDestination $bucket -UniqueWriterIdentity
        Start-Sleep -Seconds 1

        try {
            $createdSinks = Get-GcLogSink -Sink $sinkName, $sinkNameTwo
            $createdSinks | Should Not BeNullOrEmpty

            Remove-GcLogSink $sinkName, $sinkNameTwo
            { Get-GcLogSink -Sink $sinkName -ErrorAction Stop } | Should Throw "does not exist"
            { Get-GcLogSink -Sink $sinkNameTwo -ErrorAction Stop } | Should Throw "does not exist"
        }
        finally {
            Remove-GcsBucket $bucket -Force
        }
    }

    It "should work for log sink object" {
        $r = Get-Random
        $bucket = "gcloud-powershell-testing-logsink-bucket-$r"
        $sinkName = "gcps-new-gclogsink-$r"

        New-GcsBucket $bucket
        Start-Sleep -Seconds 1

        New-GcLogSink $sinkName -GcsBucketDestination $bucket -UniqueWriterIdentity
        Start-Sleep -Seconds 1

        $createdSinkObject = Get-GcLogSink -Sink $sinkName

        try {
            Remove-GcLogSink $createdSinkObject
            { Get-GcLogSink -Sink $sinkName -ErrorAction Stop } | Should Throw "does not exist"
        }
        finally {
            Remove-GcsBucket $bucket -Force
        }
    }
}
