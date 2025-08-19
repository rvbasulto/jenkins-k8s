apiVersion: apps/v1
kind: Deployment
metadata:
  name: vprofile
  namespace: jenkins
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vprofile
  template:
    metadata:
      labels:
        app: vprofile
    spec:
      containers:
        - name: vprofile
          image: 10.98.61.45:5000/vprofileappimg:latest
          ports:
            - containerPort: 8080
      imagePullSecrets:
        - name: nexus-creds
        
---
apiVersion: v1
kind: Service
metadata:
  name: vprofile
  namespace: jenkins
spec:
  selector:
    app: vprofile
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
  type: ClusterIP
