*** Settings ***
Library    SSHLibrary

*** Variables ***
${TEST_HOST}    shelf.ns8-ci.test

*** Test Cases ***
Install Shelf
    ${output}    ${rc}=    Execute Command    add-module ${IMAGE_URL} 1    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    ${result}=    Evaluate    ast.literal_eval($output)    modules=ast
    Set Suite Variable    ${module_id}    ${result}[module_id]

Configure Shelf And Supabase
    ${rc}=    Execute Command
    ...    api-cli run module/${module_id}/configure-module --data '{"host":"${TEST_HOST}","lets_encrypt":false,"saml":true}'
    ...    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0

Check Shelf And Supabase Through Traefik
    Should Not Be Empty    ${module_id}
    Check HTTPS Route    /healthcheck
    Check HTTPS Route    /login
    Check HTTPS Route    /auth/v1/health
    ${metadata}    ${rc}=    Execute Command
    ...    curl -kfSs --resolve ${TEST_HOST}:443:127.0.0.1 https://${TEST_HOST}/auth/v1/sso/saml/metadata
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    Should Contain    ${metadata}    EntityDescriptor
    Should Contain    ${metadata}    https://${TEST_HOST}/auth/v1/sso/saml/acs

Snapshot Shelf State And Restart Services
    ${rc}=    Execute Command
    ...    runagent -m ${module_id} module-dump-state
    ...    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    ${rc}=    Execute Command
    ...    runagent -m ${module_id} bash -ec 'test -s shelf-db.tar && test -s shelf-db-config.tar && test -s shelf-storage.tar'
    ...    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    Check HTTPS Route    /healthcheck
    ${rc}=    Execute Command
    ...    runagent -m ${module_id} module-cleanup-state
    ...    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0

Remove Shelf
    ${rc}=    Execute Command    remove-module --no-preserve ${module_id}    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0

*** Keywords ***
Check HTTPS Route
    [Arguments]    ${path}
    ${rc}=    Execute Command
    ...    curl -kfSs --resolve ${TEST_HOST}:443:127.0.0.1 https://${TEST_HOST}${path} >/dev/null
    ...    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0
