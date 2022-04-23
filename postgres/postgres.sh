#!/bin/bash

FTP_HOST=91.194.251.78
FTP_HOST_USER=$(printenv FTP_USER)
FTP_HOST_PASSWORD=$(printenv FTP_PASSWORD)
FOLDER_NAME=$1
DATABASE_NAME=$2
LOCAL_MOUNT_FOLDER="/mnt/ftp/"
FTP_FOLDER="postgresql/$FOLDER_NAME"
DUMPS_MINIMIZE_FOLDER="/data/postgres/dump-restore"
DATABASE_NAME_FULL=($DATABASE_NAME.sql.gz)
FOLDER_NAME_TEST="${FOLDER_NAME//./_}"
process_id=$!

# чистим консоль
# printf "\033c"

# Проверяем что поля не пустые
echo "FOLDER_NAME=${FOLDER_NAME:?}"
echo "DATABASE_NAME=${DATABASE_NAME:?}"
#echo "$FOLDER_NAME_TEST"

# Монтируем curlftpfs
curlftpfs $FTP_HOST $LOCAL_MOUNT_FOLDER -o user=$FTP_HOST_USER:$FTP_HOST_PASSWORD,allow_other

# Проверяем наличие FTP папки
echo "Check ftp folder"
if [ -d  $LOCAL_MOUNT_FOLDER/$FTP_FOLDER ]; then echo "Directory exist";
   else echo "Folder $FTP_FOLDER not found" && exit 0;
fi

# Проверяем наличие базы в FTP папке
#echo "Checking the presence of the database in the FTP folder"
#if compgen -G "$LOCAL_MOUNT_FOLDER/$FTP_FOLDER/$FOLDER_NAME_TEST*" > /dev/null; then
#    echo "pattern exists!"
#    else echo "Database not found" && exit 0;
#fi

#if [ -f  $LOCAL_MOUNT_FOLDER/$FTP_FOLDER/$FOLDER_NAME_TEST* ]; then echo "Directory exist";
#   else echo "Folder $DATABASE_NAME not found" && exit 0;
#fi

# Проверяем наличие папки возможно в данный момент идет другой рестор
echo "Checking for the presence of the folder, it is possible that another recovery is in progress at the moment"
if [ -d  $DUMPS_MINIMIZE_FOLDER/backups/$FOLDER_NAME ]; then echo "Folder $FTP_FOLDER found, what need to do? If 'y' - contine, 'n' - stop script";
   read varname
   if [[ $varname == 'n' ]]
    then exit 0;
   elif [[ $varname == 'y' ]]; then rm -rf $DUMPS_MINIMIZE_FOLDER/backups/$FOLDER_NAME/
   wait $process_id
   mkdir -p $DUMPS_MINIMIZE_FOLDER/backups/$FOLDER_NAME/;
   elif [[ $varname != 'y' ]] && [[ $varname != 'n' ]]; then exit 0; 
   fi
   else 
   echo "Directory $FOLDER_NAME create"
   mkdir -p $DUMPS_MINIMIZE_FOLDER/backups/$FOLDER_NAME; 
fi


echo "Copy database backups..."
# find last backup
BACKUP_FILE=$(ls -tr1 ${LOCAL_MOUNT_FOLDER}/${FTP_FOLDER} | egrep '\.tar.gz$' | tail -1)

# выход если что то пошло не так
set -e   

# копируем backup с ftp
cp "${LOCAL_MOUNT_FOLDER}/${FTP_FOLDER}/${BACKUP_FILE}" "${DUMPS_MINIMIZE_FOLDER}/backups/$FOLDER_NAME"
echo "Copy ${BACKUP_FILE} complited!"

# Размонтируем CurlFtpFS
fusermount -u ${LOCAL_MOUNT_FOLDER}

# распаковка backup file
echo "Unzipping ${BACKUP_FILE}..."
tar -xvzf "${DUMPS_MINIMIZE_FOLDER}/backups/$FOLDER_NAME/${BACKUP_FILE}" -C "${DUMPS_MINIMIZE_FOLDER}/backups/$FOLDER_NAME"

# перебрасываем backup file в папку
BACKUP_FILE_PATH=$(find ${DUMPS_MINIMIZE_FOLDER} -name ${DATABASE_NAME_FULL} -print | tail -1)
rm -f "${DUMPS_MINIMIZE_FOLDER}/backups/${DATABASE_NAME_FULL}"
wait $process_id
mv -f "${BACKUP_FILE_PATH}" "${DUMPS_MINIMIZE_FOLDER}/backups/$FOLDER_NAME"
rm -rf "${DUMPS_MINIMIZE_FOLDER}/backups/var"
rm -f "${DUMPS_MINIMIZE_FOLDER}/backups/$FOLDER_NAME/${BACKUP_FILE}"

# Востановить
echo "Restore minimize backup!"
docker exec -it -e DATABASE_NAME=$DATABASE_NAME -e FOLDER_NAME=$FOLDER_NAME postgresql /scripts/restore.sh 
rm -rf /data/postgres/dump-restore/backups/$FOLDER_NAME
echo "Completed, see you soon"

