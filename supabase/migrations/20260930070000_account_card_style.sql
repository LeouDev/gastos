-- Wallet card look (skin + emblem) syncs with the wallet. Card photos stay on device.
alter table public.accounts
  add column if not exists card_skin text not null default '',
  add column if not exists card_emblem text not null default '';
