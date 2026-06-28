# StabiX Ethereum Vault

## Network
Ethereum Sepolia

## Permanent Proxy Address
0x4F43855026a64afCf594d16fDF0713D262C81ee3

## Current Implementation Address
0x1a5F017651032882A8919388A11c36B1CA21aB06

## Upgrade Pattern
UUPS Upgradeable

## Notes
- All deposits go to Proxy
- All withdrawals happen through Proxy
- Merkle roots are uploaded on Proxy
- Future upgrades only change implementation
- Proxy address remains permanent
