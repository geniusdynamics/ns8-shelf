*** Settings ***
Library    SSHLibrary
Resource    shelf.resource

*** Variables ***
# Any resolvable-looking name: the schema demands a dot, nothing resolves it.
${TEST_HOST}    shelf.ns8-ci.test

*** Test Cases ***
Check if shelf is installed correctly
    ${output}  ${rc} =    Execute Command    add-module ${IMAGE_URL} 1
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ast.literal_eval($output)    modules=ast
    Set Suite Variable    ${module_id}    ${output.module_id}

Check if the secrets are generated and private
    ${mode} =    Module Home Command    ${module_id}    stat -c %a passwords.env
    Should Be Equal As Strings    ${mode.strip()}    600
    ${keys} =    Module Home Command    ${module_id}    cut -d= -f1 passwords.env | sort | xargs
    Should Contain    ${keys}    JWT_SECRET
    Should Contain    ${keys}    SESSION_SECRET
    Should Contain    ${keys}    SERVICE_ROLE_KEY

Check if the secrets are not in the module environment
    ${env} =    Module Home Command    ${module_id}    cat environment
    Should Not Contain    ${env}    JWT_SECRET
    Should Not Contain    ${env}    SESSION_SECRET
    Should Not Contain    ${env}    SERVICE_ROLE_KEY
    Should Not Contain    ${env}    AUTH_DB_PASSWORD

Check if shelf can be configured
    Run Module Action    ${module_id}    configure-module    {"host":"${TEST_HOST}","lets_encrypt":false}

Check if the configuration is rejected when invalid
    ${output}  ${rc} =    Execute Command
    ...    api-cli run module/${module_id}/configure-module --data '{"host":"${TEST_HOST}","mail_from":"not an address"}'
    ...    return_rc=True
    Should Not Be Equal As Integers    ${rc}  0

Check if shelf configuration reads back
    ${config} =    Run Module Action    ${module_id}    get-configuration
    Should Be Equal    ${config}[host]    ${TEST_HOST}
    Should Not Be True    ${config}[lets_encrypt]
    Should Not Be True    ${config}[disable_signup]
    Should Not Be True    ${config}[maptiler_token_set]

Check if get-configuration does not return secrets
    ${output} =    Execute Command    api-cli run module/${module_id}/get-configuration --data '{}'
    ${secrets} =    Module Home Command    ${module_id}    cut -d= -f2- passwords.env
    FOR    ${secret}    IN    @{secrets.split()}
        Should Not Contain    ${output}    ${secret}
    END

Check if the generated env files are private
    ${modes} =    Module Home Command    ${module_id}    stat -c %a postgres.env gotrue.env storage.env shelf.env | xargs
    Should Be Equal As Strings    ${modes.strip()}    600 600 600 600

Check if the services are running
    FOR    ${unit}    IN    shelf    postgres-app    gateway-app    gotrue-app    storage-app    shelf-app
        Wait Until Keyword Succeeds    3 min    5 sec    Unit Is Active    ${module_id}    ${unit}
    END

Check shelf health through Traefik
    # The first start applies the database migrations of Shelf
    Wait Until Keyword Succeeds    10 min    10 sec    Module Answers With Status    ${TEST_HOST}    /healthcheck    200

Check if the login page is served
    Module Answers With Status    ${TEST_HOST}    /login    200

Check supabase auth health through the gateway
    Wait Until Keyword Succeeds    3 min    5 sec    Module Answers With Status    ${TEST_HOST}    /auth/v1/health    200

Check supabase storage health through the gateway
    Wait Until Keyword Succeeds    3 min    5 sec    Module Answers With Status    ${TEST_HOST}    /storage/v1/status    200

Check if the storage buckets are created
    Wait Until Keyword Succeeds    3 min    5 sec    Storage Buckets Exist    ${module_id}    ${TEST_HOST}

Check if the database dump for the backup is consistent
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} sh -c 'cd "$AGENT_STATE_DIR" && module-dump-state'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    ${mode} =    Module Home Command    ${module_id}    stat -c %a shelf.pg_dump
    Should Be Equal As Strings    ${mode.strip()}    600
    ${size} =    Module Home Command    ${module_id}    stat -c %s shelf.pg_dump
    Should Be True    ${size.strip()} > 0
    # The dump lists the Shelf tables and the Supabase Auth and Storage schemas
    ${toc} =    Module Home Command    ${module_id}    podman exec -i postgres-app pg_restore --list < shelf.pg_dump
    Should Contain    ${toc}    TABLE public User
    Should Contain    ${toc}    TABLE auth users
    Should Contain    ${toc}    TABLE storage buckets

Check if the backup cleanup removes the dump
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} sh -c 'cd "$AGENT_STATE_DIR" && module-cleanup-state'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} sh -c 'test ! -e "$AGENT_STATE_DIR/shelf.pg_dump"'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0

Check if shelf is removed correctly
    ${rc} =    Execute Command    remove-module --no-preserve ${module_id}
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

*** Keywords ***
Unit Is Active
    [Arguments]    ${module_id}    ${unit}
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} systemctl --user is-active ${unit}.service
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
