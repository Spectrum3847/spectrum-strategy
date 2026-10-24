enum EntryDelivery {
  savedOnly('Saved on this device only'),

  pending('Waiting to send'),

  sentByQr('Sent by QR'),

  sent('Sent'),

  confirmed('In the database'),

  rejected('Not accepted');

  const EntryDelivery(this.label);

  final String label;
}
