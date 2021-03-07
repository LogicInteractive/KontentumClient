#!/bin/bash
while :
do
if [[ $(pidof KontentumClient | wc -l) -eq 0 ]]; then
    sudo /home/tommy/KontentumClient/KontentumClient #run the kontentum client if not already running - (check folder)
fi
sleep 2
done