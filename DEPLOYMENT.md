sudo source .env

sudo forge script script/Deploy.s.sol:Deploy \
  --rpc-url $RPC_URL \
  --broadcast --verify --legacy --resume \
  --private-key $PRIVATE_KEY \
  --retries 10 --delay 5

sudo forge clean
sudo source .env
sudo forge script script/Deploy.s.sol:Deploy \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  -vvvv

source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  -vvvv

forge verify-contract \
  0x1B3634c085B1748f051689e5891d7Aa3B63b6898 \
  src/Verifier.sol:Verifier \
  --chain-id 4202 \
  --verifier blockscout \
  --verifier-url https://sepolia-blockscout.lisk.com/api


# BASE SEPOLIA
  → new DustToken@0xb54e25Db229942E8E9360613A46A72cf0f92E83c
  → new Identity@0xa171051a408E9720D587A80247977d596dB37614
  → new Core@0x9dF9F9952cF743542Cf97337EfA37Ae936E669B7
  → new Content@0x7F9194dD652a4A4796c01a5a625a2aC71017fB2c
  → new Jobs@0x245b947434a2C28134f6d6C26eB57962e11bc1b0
  → new Verifier@0xbca221bCcf6c4cF32d1e578b75eC53fA697c0979

# LISK SEPOLIA
  → new DustToken@0x94787488e2D165C62DFa0607c32EF1f32C23C69a
  → new Identity@0x0515Fe26095dEc1c3ACC64c11D70dad52d9668f5
  → new Core@0x46F50b5D9FEaaC19a95d30834042fa8640B5417C
  → new Content@0x32478a142D06752BCF678f9BCFA2e61f47E937de
  → new Jobs@0x9912f17F95e85b930787836B5EDa2192b1172C6C
  → new Verifier@0x1B3634c085B1748f051689e5891d7Aa3B63b6898