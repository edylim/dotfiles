#!/bin/bash

# --- Helper functions for UI ---
ESC=$(printf "\033")
cursor_blink_on()   { printf "$ESC[?25h"; }
cursor_blink_off()  { printf "$ESC[?25l"; }
cursor_to()         { printf "$ESC[$1;${2:-1}H"; }
print_inactive()    { printf "[ ] %s" "$1"; }
print_active()      { printf "$ESC[7m[ ] %s$ESC[27m" "$1"; }
print_selected()    { printf "[✔] %s" "$1"; }
print_selected_active() { printf "$ESC[7m[✔] %s$ESC[27m" "$1"; }
get_cursor_row()    { IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${ROW#*[}; }

# --- Options ---
options=(
    "zsh - Zsh shell with Prezto framework"
    "git - Git configuration for version control"
    "homebrew - Package Manager"
    "kitty - A fast, feature-rich, GPU-based terminal"
    "awrit - A Chromium browser in terminal"
    "grumpyvim - An opinionated neovim implementation"
    "lint files - ESLint and Prettier for code formatting and style"
    "yazi - A terminal file manager"
    "presenterm - A terminal presentation deck"
)

# --- State ---
selected=()
for i in "${!options[@]}"; do
    selected+=("true")
done
active=0

# --- Main UI Logic ---

# Trap CTRL+C
trap "cursor_blink_on; stty echo; printf '\n'; exit" 2

# Clear screen and hide cursor
clear
cursor_blink_off

# Print title and instructions
echo "Select packages to setup:"
echo
echo "j or ↓       to move down"
echo "k or ↑       to move up"
echo "⎵ (space)    to toggle selection"
echo "⏎ (enter)    to confirm"
echo

# Print options
for i in "${!options[@]}"; do
    echo
done

# Determine start row
lastrow=$(get_cursor_row)
startrow=$(($lastrow - ${#options[@]}))

print_options() {
    local idx=0
    for option in "${options[@]}"; do
        cursor_to $(($startrow + $idx))
        if [[ ${selected[idx]} == true ]]; then
            if [ $idx -eq $active ]; then
                print_selected_active "$option"
            else
                print_selected "$option"
            fi
        else
            if [ $idx -eq $active ]; then
                print_active "$option"
            else
                print_inactive "$option"
            fi
        fi
        ((idx++))
    done
}

key_input() {
    local key
    IFS= read -rsn1 key 2>/dev/null >&2
    if [[ $key = ""      ]]; then echo enter; fi;
    if [[ $key = $'\x20' ]]; then echo space; fi;
    if [[ $key = "k" ]]; then echo up; fi;
    if [[ $key = "j" ]]; then echo down; fi;
    if [[ $key = $'\x1b' ]]; then
        read -rsn2 key
        if [[ $key = [A || $key = k ]]; then echo up;    fi;
        if [[ $key = [B || $key = j ]]; then echo down;  fi;
    fi 
}

# --- Main Loop ---
while true; do
    print_options

    case $(key_input) in
        space)
            if [[ ${selected[active]} == true ]]; then
                selected[active]=false
            else
                selected[active]=true
            fi
            ;;
        enter)
            break
            ;;
        up)
            ((active--))
            if [ $active -lt 0 ]; then active=$((${#options[@]} - 1)); fi
            ;;
        down)
            ((active++))
            if [ $active -ge ${#options[@]} ]; then active=0; fi
            ;;
    esac
done

# --- Cleanup ---
cursor_to $lastrow
printf "\n"
cursor_blink_on

doinstall=false

# --- Output selected ---
for i in "${!options[@]}"; do
    if [ "${selected[$i]}" = "true" ]; then
        doinstall=true
    fi
done

if [[ ${doinstall} == true ]]; then
    echo "Installing..."
fi
    
