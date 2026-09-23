Feature: Verify ambox end to end
  Scenario: Bootstrap connected storage and display its records
    Given ambox is running
    Then Storage Service is connected to the advertised Archivematica pipeline
    And the storage configuration is visible in Storage Service

  Scenario: Process pictures through mounted transfer, AIP, and DIP storage
    Given ambox is running
    And Storage Service is connected to the advertised Archivematica pipeline
    And the Dashboard login page is available
    And the ClamAV daemon shares its version
    When the bundled pictures are uploaded through SFTP and submitted with automated processing
    Then the transfer completes
    And transfer jobs and tasks are exposed by the API
    And the ClamAV scan completes successfully
    And the SIP completes ingest
    And ingest jobs and tasks are exposed by the API
    And the AIP and DIP are uploaded to Storage Service
    And the AIP and DIP are listed by the Storage Service API
    And the AIP and DIP are visible in Storage Service
    And the completed workflow is visible in Dashboard
