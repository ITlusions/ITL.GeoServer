{{/*
Keystore generator init container
This can be used as an alternative to the job-based approach
*/}}
{{- define "geoserver.keystoreInitContainer" -}}
{{- if and .Values.https.enabled .Values.https.autoGenerateKeystore (not .Values.https.keystoreSecret) .Values.https.keystoreGenerator.useInitContainer }}
- name: keystore-generator
  image: {{ .Values.https.keystoreGenerator.image | default "docker.io/alpine/openssl:latest" }}
  imagePullPolicy: IfNotPresent
  command:
    - /bin/sh
    - -c
    - |
      set -e
      
      echo "Checking if keystore exists..."
      if [ -f /opt/geoserver/keystore.jks ]; then
        echo "Keystore already exists, skipping generation"
        exit 0
      fi
      
      echo "Installing required packages..."
      apk add --no-cache openjdk11-jre-headless curl
      
      DOMAIN="{{ .Values.https.keystoreGenerator.domain | default "geoserver.local" }}"
      ORG="{{ .Values.https.keystoreGenerator.organization | default "GeoServer" }}"
      COUNTRY="{{ .Values.https.keystoreGenerator.country | default "US" }}"
      VALIDITY="{{ .Values.https.keystoreGenerator.validityDays | default 365 }}"
      KEY_ALIAS="{{ .Values.https.keyAlias | default "server" }}"
      
      # Generate random password if not provided
      if [ -z "$KEYSTORE_PASSWORD" ]; then
        KEYSTORE_PASSWORD=$(openssl rand -base64 32)
        echo "Generated random keystore password"
      fi
      
      echo "Starting keystore generation..."
      echo "Domain: $DOMAIN"
      echo "Organization: $ORG"
      echo "Country: $COUNTRY"
      echo "Validity: $VALIDITY days"
      
      # Generate private key
      echo "Generating private key..."
      openssl genrsa -out /tmp/server.key 2048
      
      # Create certificate signing request
      echo "Creating certificate signing request..."
      openssl req -new -key /tmp/server.key -out /tmp/server.csr \
          -subj "/CN=$DOMAIN/O=$ORG/C=$COUNTRY"
      
      # Create certificate extensions file
      cat > /tmp/server.ext << EOF
      authorityKeyIdentifier=keyid,issuer
      basicConstraints=CA:FALSE
      keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
      subjectAltName = @alt_names
      
      [alt_names]
      DNS.1 = $DOMAIN
      DNS.2 = localhost
      DNS.3 = *.svc.cluster.local
      DNS.4 = *.{{ .Release.Namespace }}.svc.cluster.local
      IP.1 = 127.0.0.1
      EOF
      
      # Generate self-signed certificate
      echo "Generating self-signed certificate..."
      openssl x509 -req -in /tmp/server.csr -signkey /tmp/server.key \
          -out /tmp/server.crt -days $VALIDITY \
          -extensions v3_req -extfile /tmp/server.ext
      
      # Create PKCS12 keystore
      echo "Creating PKCS12 keystore..."
      openssl pkcs12 -export -in /tmp/server.crt -inkey /tmp/server.key \
          -out /tmp/keystore.p12 -name "$KEY_ALIAS" \
          -password pass:"$KEYSTORE_PASSWORD"
      
      # Convert to JKS keystore
      echo "Converting to JKS keystore..."
      keytool -importkeystore \
          -srckeystore /tmp/keystore.p12 -srcstoretype PKCS12 \
          -destkeystore /opt/geoserver/keystore.jks -deststoretype JKS \
          -srcstorepass "$KEYSTORE_PASSWORD" \
          -deststorepass "$KEYSTORE_PASSWORD" \
          -noprompt
      
      # Set proper permissions
      chmod 644 /opt/geoserver/keystore.jks
      chown 999:999 /opt/geoserver/keystore.jks
      
      # Save password to shared file
      echo "$KEYSTORE_PASSWORD" > /opt/geoserver/.keystore-password
      chmod 600 /opt/geoserver/.keystore-password
      chown 999:999 /opt/geoserver/.keystore-password
      
      echo "Keystore generation completed successfully!"
      echo "Keystore saved to: /opt/geoserver/keystore.jks"
      echo "Password saved to: /opt/geoserver/.keystore-password"
      
      # Clean up temporary files
      rm -f /tmp/server.key /tmp/server.csr /tmp/server.crt /tmp/server.ext /tmp/keystore.p12
      
      echo "Cleanup completed."
  env:
    - name: KEYSTORE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ include "geoserver.fullname" . }}-https
          key: keystorePassword
          optional: true
  volumeMounts:
    - name: geoserver-data
      mountPath: /opt/geoserver
  securityContext:
    runAsNonRoot: true
    runAsUser: 999
    runAsGroup: 999
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: false
    capabilities:
      drop:
        - ALL
  resources:
    {{- toYaml (.Values.https.keystoreGenerator.resources | default (dict "limits" (dict "cpu" "100m" "memory" "128Mi") "requests" (dict "cpu" "50m" "memory" "64Mi"))) | nindent 4 }}
{{- end }}
{{- end }}
