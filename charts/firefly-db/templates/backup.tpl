{{ define "backupJobSpec" }}
spec:
  containers:
  - name: {{ template "firefly-db.fullname" . }}-backup-job
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
    imagePullPolicy: IfNotPresent
    envFrom:
    - configMapRef:
        name: {{ template "firefly-db.fullname" . }}-config
    command:
    - /bin/sh
    - -c
    - |
      set -e
      mkdir -p /var/lib/backup
      backupFile="/var/lib/backup/{{ .Values.backup.filename }}"

      {{- if eq .Values.global.config.env.DB_CONNECTION "mysql" }}
      # on the mysql side we already have gzip and curl installed
      # Todo: handle other versions of mysql
      echo "Creating backup file $backupFile"
      mysqldump -h $DB_HOST -P $DB_PORT -u $MYSQL_USER --password="$MYSQL_PASSWORD" --single-transaction --no-tablespaces --routines --triggers --events --add-drop-database --add-drop-table --databases $MYSQL_DATABASE {{ if .Values.backup.gzip }} | gzip {{- end }} > $backupFile
      {{- end }}

      {{- if eq .Values.global.config.env.DB_CONNECTION "pgsql" }}
      apk update
      apk add postgresql
      {{- if .Values.backup.gzip }}
      apk add gzip
      {{- end }}
      {{- if eq .Values.backup.destination "http" }}
      apk add curl
      {{- end }}
      echo "Creating backup file $backupFile"
      pg_dump -h $DB_HOST -p $DB_PORT -U $DB_USER --format=p --clean -d $DB_NAME {{ if .Values.backup.gzip }} | gzip {{- end }} > $backupFile
      {{- end }}

      {{- if eq .Values.backup.destination "http" }}
      echo "uploading backup file"
      curl -F "filename=@$backupFile" $BACKUP_URL
      {{- end }}

      echo "done"
    volumeMounts:
      {{- with .Values.backup.extraVolumeMounts }}
        {{- toYaml . | nindent 10 }}
      {{- end }}
      {{- if .Values.backup.pvc.enabled }}
      - name: backup-storage
        mountPath: /var/lib/backup
      {{- end }}
  restartPolicy: Never
  volumes:
    {{- with .Values.backup.extraVolumes }}
      {{- toYaml . | nindent 2 }}
    {{- end }}
    {{- if .Values.backup.pvc.enabled }}
    - name: backup-storage
      persistentVolumeClaim:
        claimName: {{ default (printf "%s-%s" (include "firefly-db.fullname" .) "backup-storage-claim") .Values.backup.pvc.existingClaim }}
    {{- end }}
{{ end }}
