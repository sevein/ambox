Feature: Verify ambox end to end
  Scenario: Process the bundled pictures into an AIP
    Given ambox is running
    And the Dashboard login page is available
    And the ClamAV daemon shares its version
    When the bundled pictures are submitted with automated processing
    Then the transfer completes
    And transfer jobs and tasks are exposed by the API
    And the ClamAV scan completes successfully
    And the SIP completes ingest
    And ingest jobs and tasks are exposed by the API
    And the AIP is uploaded to Storage Service
    And the completed workflow is visible in Dashboard
