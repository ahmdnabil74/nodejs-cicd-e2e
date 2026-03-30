FROM node:18-alpine

WORKDIR /usr/src/app

COPY package*.json ./
# have versions of modules on nodejs
RUN npm install

COPY . .
#copy all file in the dir into the image d
EXPOSE 8000

CMD [ "node", "app.js" ]

###### docker build -t node-app-img .
###### docker run -d --name node-container -p 8000:8000 node-app-img
# i want to connect that container with postgres db
#it must container on same network with db of postgres 
# because container is in isolated envorinment and will not see anything running or in another continer
# must attach container in network host 
# it will help container to connect with another things running on pc 

####### docker stop node-container
####### docker rm node-container
###### docker run -d --name node-container -p 8000:8000 --network host node-app-img
