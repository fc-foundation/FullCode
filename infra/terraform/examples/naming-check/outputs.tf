output "generated_names" {
  description = "resource_type -> generated name for every entry in modules/naming's resource_types table. Consumed by policy/naming.rego in CI."
  value = {
    resource_group         = module.resource_group.name
    virtual_network        = module.virtual_network.name
    subnet                 = module.subnet.name
    network_security_group = module.network_security_group.name
    public_ip              = module.public_ip.name
    route_table            = module.route_table.name
    storage_account        = module.storage_account.name
    key_vault              = module.key_vault.name
  }
}
