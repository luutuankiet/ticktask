#!/bin/bash

ACCESS_TOKEN_FILE="$HOME/.cache/ticktask/token"
CONFIG_FILE="$HOME/.config/ticktask/config.sh"
FOLDER_ERROR_TASKS="$HOME/.cache/ticktask/error_tasks/"

if [ -z "$1" ]; then
    echo "Usage: $0 your task title"

    exit 1
fi

task_title=$(echo "$@" | sed 's/\\/\\\\/g; s/"/\\"/g')
echo "input task description if any: "

# open a vim file to allow multiline; clear the content before input
echo " " > /tmp/tickticktemp.txt
vim /tmp/tickticktemp.txt
user_input_raw=$(cat /tmp/tickticktemp.txt)

# format the input to add \n for each line
user_input=$(echo $user_input_raw | sed ':a;N;$!ba;s/\n/\\\n/g;s/"/\\"/g' )

if [ -n "$user_input" ]; then # check if body exists then append json format. requires gxmessage util install - sudo apt install gxmessage
     task_body=', "content": "'$user_input'"'
fi

if [ ! -f $CONFIG_FILE ]; then
    echo "Please create config file: $CONFIG_FILE"

    exit 1
fi

source $CONFIG_FILE

if [ -f $ACCESS_TOKEN_FILE ]; then
    access_token=$(<$ACCESS_TOKEN_FILE)
else
    # authorization
    echo "No access_token cached. Receiving new one"

    REDIRECT_URL="http://127.0.0.1"
    URL_LEN=$(echo "$REDIRECT_URL" | wc -c)

    # docs says "comma separated", but comma not work. So we use space there
    SCOPE="tasks:write%20tasks:read"

    auth_url="https://ticktick.com/oauth/authorize?scope=$SCOPE&client_id=$CLIENT_ID&state=state&redirect_uri=$REDIRECT_URL&response_type=code"

    echo "Opening browser"
    user_auth_url=$(curl -ILsS -w "%{url_effective}\n" "$auth_url" | tail -n1)
    xdg-open $user_auth_url 2> /dev/null

    read -ep "Paste url you've been redirected: " url_with_code
    code=$(echo -n $url_with_code | tail -c +$(($URL_LEN + 7)) | head -c 6)
    echo "Code: $code"

    payload_get_acces_token="grant_type=authorization_code&code=$code&redirect_uri=$REDIRECT_URL"
    resp_get_access_token=$(curl -s --header "Content-Type: application/x-www-form-urlencoded" \
        -u $CLIENT_ID:$CLIENT_SECRET \
        --request POST \
        --data "$payload_get_acces_token" \
        https://ticktick.com/oauth/token)

    # TODO: store parameter expires_in
    if [[ $resp_get_access_token =~ (access_token\":\")([^\"]*) ]]; then
        access_token=${BASH_REMATCH[2]}
        echo "access_token received. You can find it in $ACCESS_TOKEN_FILE"

        mkdir -p $(dirname $ACCESS_TOKEN_FILE)
        echo -n "$access_token" > $ACCESS_TOKEN_FILE
    else
        echo "Bad response for getting access_token: $resp_get_access_token"

        exit 2
    fi
fi

# parse date
if [[ $task_title =~ (^| )\*(today|tomorrow)( |$).* ]]; then
    title_date=${BASH_REMATCH[2]}
    # date must be 1 day ago than real
    title_date=$(date --date="$title_date 1 day ago" -Iseconds)
    field_duedate=', "dueDate": "'$title_date'"'

    # remove date entries from title text
    task_title="$(echo "$task_title" | sed -E 's/(^| )\*today( |$)/ /g; s/(^| )\*tomorrow( |$)/ /g; s/(^ | $)//g')"
fi
# parse tags
if [[ $task_title =~ (^| )#([a-zA-Z0-9_]+)( |$) ]]; then
    tags=$(echo "$task_title" | grep -Eo "(^| )#\w+" | tr -d "\n")

    # HACK. desc is not actual description (for real description use field
    # 'content'). This field is not even displayed (at least in web version),
    # but ticktick parses tags from this field
    field_desc=', "desc": "'$tags'"'

    # remove tags from title text
    task_title="$(echo "$task_title" | sed -E 's/(^| )(#\w+( |$))+/ /g; s/(^ | $)//g')"
fi

json_task='{ "title": "'$task_title'"'$task_body''$field_duedate$field_desc' }'

# finally send request to create task
resp_create_task=$(curl -s \
    --fail-with-body \
    --header "Content-Type: application/json" \
    --header "Authorization: Bearer $access_token" \
    --request POST \
    --data "$json_task" \
    https://api.ticktick.com/open/v1/task)
if (( $? != 0 )); then
    echo "Error on creating task. Server response:"
    echo "$resp_create_task"

    mkdir -p $FOLDER_ERROR_TASKS
    error_task_file=$(date +%s)
    echo "$@" > $FOLDER_ERROR_TASKS/$error_task_file
    echo "Task saved to $FOLDER_ERROR_TASKS"

    exit 2
fi
kill -9 $PPID
