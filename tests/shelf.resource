*** Settings ***
Library    SSHLibrary

*** Keywords ***
Run Module Action
    [Arguments]    ${module_id}    ${action}    ${data}={}
    ${output}  ${rc} =    Execute Command    api-cli run module/${module_id}/${action} --data '${data}'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0    ${action} failed
    ${result} =    Evaluate    json.loads($output) if $output.strip() else {}    modules=json
    RETURN    ${result}

Module HTTP Status
    [Documentation]    HTTP status code of a GET to the module through Traefik. The host name
    ...    does not resolve in the test node, so it is pinned to the loopback address.
    [Arguments]    ${host}    ${path}
    ${output}  ${rc} =    Execute Command
    ...    curl --silent --output /dev/null --write-out '\%{http_code}' --insecure --resolve ${host}:443:127.0.0.1 https://${host}${path}
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    RETURN    ${output}

Module Answers With Status
    [Arguments]    ${host}    ${path}    ${expected}
    ${status} =    Module HTTP Status    ${host}    ${path}
    Should Be Equal As Strings    ${status}    ${expected}    ${path} answered ${status}

Module Home Command
    [Documentation]    Run a shell command as the module, in the state directory.
    [Arguments]    ${module_id}    ${command}
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} sh -c 'cd "$AGENT_STATE_DIR" && ${command}'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0    ${command} failed
    RETURN    ${output}

Storage Buckets Exist
    [Arguments]    ${module_id}    ${host}
    # The service role key stays in the remote shell: it is never printed
    ${output}  ${rc} =    Execute Command
    ...    runagent -m ${module_id} sh -c 'cd "$AGENT_STATE_DIR" && key=$(grep "^SERVICE_ROLE_KEY=" passwords.env | cut -d= -f2-) && curl --silent --fail --insecure --resolve ${host}:443:127.0.0.1 -H "Authorization: Bearer $key" -H "apikey: $key" https://${host}/storage/v1/bucket'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    ${buckets} =    Evaluate    sorted(b["name"] for b in json.loads($output))    modules=json
    Should Be Equal    ${buckets}    ${{ ["assets", "files", "kits", "profile-pictures"] }}
