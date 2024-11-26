#!/bin/bash

echo "Welcome to the password generator"
echo "Please enter the length of the password:"
read PASS_LENGTH

if ! [[ $PASS_LENGTH =~ ^[0-9]+$ ]]; then
    echo "Error: Please enter a valid number."
    exit 1
fi

passwords=()
for p in $(seq 1 3); do
    passwords+=("$(openssl rand -base64 48 | cut -c1-$PASS_LENGTH)")
done

echo "Here are the generated passwords:"
printf "%s\n" "${passwords[@]}"

echo "Do you want to save these passwords to a file? (y/n)"
read choice

if [ "$choice" = "y" ]; then
    echo "Please enter a passphrase for encryption:"
    read -s PASSPHRASE

    # Save passwords to a temporary file
    for password in "${passwords[@]}"; do
        echo "$password" >> temp_passwords.txt
    done

    # Encrypt using GPG
    echo "$PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 temp_passwords.txt

    mv temp_passwords.txt.gpg passwords.txt.gpg
    echo "Passwords saved securely to passwords.txt.gpg"

    # Clean up plaintext file
    rm -f temp_passwords.txt

elif [ "$choice" = "n" ]; then
    echo "Passwords not saved."
else
    echo "Invalid choice. Exiting."
fi



# Todo - if want to see the password text file means use this command to run in terminal 
# gpg --decrypt passwords.txt.gpg
# Then enter the PASSPHRASE to unlock it.