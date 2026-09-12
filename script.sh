
az network vnet peering create \
    --name JPVNetSpoke1-to-JPVNetSpoke2 \
    --vnet-name JPVNetSpoke1 \
    --remote-vnet JPVNetSpoke2 \
    --resource-group rg-az500-doit-cus \
    --allow-forwarded-traffic


az network vnet peering create \
    --name JPVNetSpoke2-to-JPVNetSpoke1 \
    --vnet-name JPVNetSpoke2 \
    --remote-vnet JPVNetSpoke1 \
    --resource-group rg-az500-doit-cus \
    --allow-forwarded-traffic

