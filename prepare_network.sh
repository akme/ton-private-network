#!/usr/bin/env bash
set -x
if [[ "$GENESIS" == 1 ]]; then
cd keyring
read -r VAL_ID_HEX VAL_ID_BASE64 <<< $(generate-random-id -m keys -n validator)
cp validator $VAL_ID_HEX
fift -s <<< $(echo '"validator.pub" file>B 4 B| nip "validator-keys.pub" B>file')
echo "Validator key short_id "$VAL_ID_HEX
export VAL_ID_HEX=$VAL_ID_HEX
mv validator-keys.pub ../../contracts
cd ../../contracts
./create-state gen-zerostate.fif
ZEROSTATE_FILEHASH=$(sed ':a;N;$!ba;s/\n//g' <<<$(sed -e "s/\s//g" <<<"$(od -An -t x1 zerostate.fhash)") | awk '{ print toupper($0) }')
mv zerostate.boc ../db/static/$ZEROSTATE_FILEHASH
BASESTATE0_FILEHASH=$(sed ':a;N;$!ba;s/\n//g' <<<$(sed -e "s/\s//g" <<<"$(od -An -t x1 basestate0.fhash)") | awk '{ print toupper($0) }')
mkdir ../db/import
mv basestate0.boc ../db/static/$BASESTATE0_FILEHASH
cd ../db
sed -e "s#ROOT_HASH#$(cat ../contracts/zerostate.rhash | base64)#g" -e "s#FILE_HASH#$(cat ../contracts/zerostate.fhash | base64)#g" ton-private-testnet.config.json.template > my-ton-global.config.json
IP=$PUBLIC_IP; IPNUM=0; for (( i=0 ; i<4 ; ++i )); do ((IPNUM=$IPNUM+${IP%%.*}*$((256**$((3-${i})))))); IP=${IP#*.}; done
[ $IPNUM -gt $((2**31)) ] && IPNUM=$(($IPNUM - $((2**32))))

mkdir dht-server
cd dht-server
cp ../my-ton-global.config.json .
wget https://test.ton.org/ton-global.config.json
dht-server -C ton-global.config.json -D . -I "$PUBLIC_IP:$DHT_PORT"

DHT_NODES=$(generate-random-id -m dht -k keyring/* -a "{
             \"@type\": \"adnl.addressList\",
             \"addrs\": [
               {
                 \"@type\": \"adnl.address.udp\",
                 \"ip\":  $IPNUM,
                 \"port\": $DHT_PORT
               }
             ],
             \"version\": 0,
             \"reinit_date\": 0,
             \"priority\": 0,
             \"expire_at\": 0
           }")

sed -i -e "s#NODES#$(printf "%q" $DHT_NODES)#g" my-ton-global.config.json
cp my-ton-global.config.json ..
#mkdir dht-server
#cd dht-server
#cp ../my-ton-global.config.json .
#cp ../keyring/* keyring
#dht-server -C my-ton-global.config.json -D . -I "$PUBLIC_IP:$DHT_PORT"
dht-server -C my-ton-global.config.json -D . -I "$PUBLIC_IP:$DHT_PORT"&
cd ..
./node_init.sh
(validator-engine -C /var/ton-work/db/my-ton-global.config.json --db /var/ton-work/db --ip "$PUBLIC_IP:$PUBLIC_PORT")&
PRELIMINARY_VALIDATOR_RUN=$!
sleep 4;
read -r t1 t2 t3 NEW_NODE_KEY <<< $(echo | validator-engine-console -k client -p server.pub -v 0 -a  "$PUBLIC_IP:$CONSOLE_PORT" -rc "newkey"|tail -n 1)
read -r t1 t2 t3 NEW_VAL_ADNL <<< $(echo | validator-engine-console -k client -p server.pub -v 0 -a  "$PUBLIC_IP:$CONSOLE_PORT" -rc "newkey"|tail -n 1)

echo | validator-engine-console -k client -p server.pub -v 0 -a  "$PUBLIC_IP:$CONSOLE_PORT" -rc "addpermkey $VAL_ID_HEX 0 $(($(date +"%s")+31414590))" 2>&1
echo | validator-engine-console -k client -p server.pub -v 0 -a  "$PUBLIC_IP:$CONSOLE_PORT" -rc "addtempkey $VAL_ID_HEX $VAL_ID_HEX $(($(date +"%s")+31414590))" 2>&1
echo | validator-engine-console -k client -p server.pub -v 0 -a  "$PUBLIC_IP:$CONSOLE_PORT" -rc "addadnl $NEW_VAL_ADNL 0" 2>&1
echo | validator-engine-console -k client -p server.pub -v 0 -a  "$PUBLIC_IP:$CONSOLE_PORT" -rc "addadnl $VAL_ID_HEX 0" 2>&1

echo | validator-engine-console -k client -p server.pub -v 0 -a  "$PUBLIC_IP:$CONSOLE_PORT" -rc "addvalidatoraddr $VAL_ID_HEX $NEW_VAL_ADNL $(($(date +"%s")+31414590))" 2>&1
echo | validator-engine-console -k client -p server.pub -v 0 -a  "$PUBLIC_IP:$CONSOLE_PORT" -rc "addadnl $NEW_NODE_KEY 0" 2>&1
echo | validator-engine-console -k client -p server.pub -v 0 -a  "$PUBLIC_IP:$CONSOLE_PORT" -rc "changefullnodeaddr $NEW_NODE_KEY" 2>&1
echo | validator-engine-console -k client -p server.pub -v 0 -a "$PUBLIC_IP:$CONSOLE_PORT" -rc "importf keyring/$VAL_ID_HEX" 2>&1
kill $PRELIMINARY_VALIDATOR_RUN;
else
  sleep 10
  wget ${CONFIG}
  head -n -10 my-ton-global.config.json > tmp.config
  mv tmp.config my-ton-global.config.json
  echo "}}}" >> my-ton-global.config.json
  cat my-ton-global.config.json
  ./node_init.sh

fi