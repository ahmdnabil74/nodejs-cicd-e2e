docker run -d --name postgres-container -p 5432:5432 -e POSTGRES_PASSWORD=mypassword -v postgres_volume:/var/lib/postgresql postgres:latest
docker image ls -a
docker ps
#################
CONTAINER ID   IMAGE             COMMAND                  CREATED         STATUS         PORTS                                         NAMES
dcae02723faf   postgres:latest   "docker-entrypoint.s…"   2 minutes ago   Up 2 minutes   0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp   postgres-container
####################

docker exec -it postgres-container bash
root@dcae02723faf:/# psql -U postgres
\l # list of DB
postgres=# create database psql_db; # create db

psql_db=# create table my_table (id int, name varchar(255)); #create table

\dt # show tables

psql_db=# insert into my_table (id, name) values (1, 'php'),(2, 'java'),(3,'python');
psql_db=# select * from my_table #show content of table 
psql_db=# drop table my_table; #drop table and delete
psql_db=# \dt
psql_db=# \q # to exit db 
######################
node app.js
sudo systemctl start postgresql.service
sudo status postgresql

##################################################################
#### install portainer ####################################3
docker volume create portainer_data
docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart always 
-v \\.\pipe\docker_engine:\\.\pipe\docker_engine -v portainer_data:C:\data portainer/portainer-ce:lts

########################################

in app.yml
docker build -t triple3a/nodejs-app:latest





####################### k8s commands ########################
@@@@@@@ in app.yml
kubectl create secret generic db-password-secret --from-literal=DB_PASSWORD=asjfnasjfasjfn
# secret has name , key , value 
# we use secret to store sensitive data like password and we can use it in our deployment file to inject it as env variable in our container
# genric is type of secret and we can create other types of secret like docker-registry-secret to store docker registry credentials and tls-secret to store tls certificates
# Secret عادي تخزن فيه أي key/value (زي password أو API key)
# --from-literal : take value from command line and create secret from it not from file
kubectl delete secret db-password-secret
kubectl create -n nodejs-app secret generic db-password-secret --from-literal=DB_PASSWORD=asjfnasjfasjfn
kubectl create namespace nodejs-app
kubectl apply -n nodejs-app -f k8s/
kubectl get pvc -n nodejs-app