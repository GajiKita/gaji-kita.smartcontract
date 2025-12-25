Gaji Kita smart-contract notes
-----------------------------
- Foundry project on solc 0.8.30 (via IR, optimizer on). Depends on OpenZeppelin ERC721 only; custom libraries in `src/utils`.
- Main entry is `src/GajiKita.sol`, composing modules for companies, employees, liquidity, withdrawals, fees, and receipt NFTs. Ownership comes from `ReceiptNFTModule` (`owner()` is set once in the constructor); operational access is enforced through an `admins` mapping. `initialize(address)` only seeds the `admins` map for proxy deployments and can be called by anyone, but does not protect against multiple calls.

Arsitektur dan alur inti
- Identitas perusahaan dan employee adalah address; `CompanyModule.onlyCompany`/`EmployeeModule.onlyEmployee` menegakkan bahwa pemilik = address itu sendiri. Admin (owner atau admin tambahan) yang mendaftarkan perusahaan dan menambah karyawan.
- Liquidity: perusahaan mengunci ETH dengan `lockCompanyLiquidity` (harus `msg.value == _amount`) dan investor menambah dana dengan `depositInvestorLiquidity`. Pool liquidity tercatat di `poolData.totalLiquidity`; likuiditas investor saja dilacak di `totalInvestorLiquidity`.
- Penarikan gaji: employee dapat tarik hingga min((salary/30 * daysWorked), 30% salary). `_withdrawEmployeeSalary` memotong fee, mengurangi pool liquidity, menambah `platformFeeBalance` dan `companies[companyId].rewardBalance`, lalu mendistribusikan bagian investor secara pro-rata ke `investors[*].rewardBalance` berdasarkan share likuiditas.
- Rewards/fee: default konfigurasi di konstruktor = 80% platform, 20% company, 0% investor, fee 1% (100 bps). Distribusi fee kini menyalurkan porsi investor; investor dapat menarik reward akumulatifnya.
 - Akses kontrol: owner ditentukan oleh konstruktor `ReceiptNFTModule` dan tidak bisa di-transfer; admin adalah mapping yang bisa ditambah/dihapus oleh owner/admin. Fungsi `initialize` hanya men-set admin saat lewat proxy dan bisa dipanggil siapa saja (idempotent pada alamat yang sama).
 - Token settlement & router: konstruktor sekarang menerima `settlementToken` dan `router` per deploy. Jika `settlementToken` non-zero, ERC20 mode aktif sejak awal, router wajib non-zero, dan event `Erc20Initialized` dipicu. Jika zero, kontrak berjalan mode ETH legacy; employee masih bisa memilih payout token saat ERC20 diaktifkan.
- Status perusahaan: setiap company punya `status` (Enabled/Disabled). Admin/owner dapat memanggil `enableCompany`/`disableCompany`; `onlyCompany` dan penambahan karyawan memeriksa status ini, sehingga perusahaan yang disabled tidak bisa mengunci likuiditas atau menerima karyawan baru hingga di-enable kembali.
- Alamat perusahaan dapat diganti oleh admin/owner melalui `updateCompanyAddress(oldAddr, newAddr)`. Migrasi memindahkan data perusahaan, memperbarui `companyList`, dan mengalihkan `companyId` pada seluruh karyawan. Pastikan `newAddr` belum terdaftar.
- Receipt NFT: setiap transaksi utama memanggil `_mintReceipt` pada `ReceiptNFTModule` (soulbound ERC721). Metadata yang tersimpan: `txType`, `amount`, `timestamp`, `cid`.
- Proxy: `src/Proxy.sol` adalah proxy minimal dengan storage slot custom dan `delegatecall` di fallback/receive. Tidak ada fungsi upgrade/admin; test memanipulasi slot langsung (`vm.store`). Tidak ada guard terhadap proxy-call reentrancy.

Liquidity & Investor Reward Model
- Investor berperan sebagai LP; deposit menambah `totalInvestorLiquidity` dan total pool. Saat employee withdraw, fee dibagi platform/company/investor dan porsi investor didistribusikan pro-rata: `rewardShare = deposited / totalInvestorLiquidity * investorPart`. Reward akumulatif disimpan di `investors[*].rewardBalance` dan dapat ditarik terpisah dari principal; penarikan reward boleh parsial/utuh selama tidak melebihi saldo.
- Invariant: menghitung `investorPart` tanpa mendistribusikan dianggap bug bisnis; reward investor tidak boleh di-drop diam-diam.

- Catatan risiko/ketidaklengkapan
- Distribusi investor reward memakai loop per investor (naif, O(n)); cukup untuk MVP, perlu index-based accounting untuk skala besar.
 - Disable company tidak menarik/menahan saldo apa pun; admin harus mengelola implikasi bisnis sendiri (tidak ada auto-refund/liquidation).
- Update alamat perusahaan melakukan loop atas `companyList` dan `employeeList` (O(n)); gas dapat membesar bila daftar panjang.
- `rewardBalance` perusahaan hanya bertambah dari potongan fee saat employee withdraw; `withdrawCompanyReward` akan revert bila belum ada fee yang dikumpulkan.
- Tidak ada mekanisme transfer ownership atau pause; admin mapping bisa ditambah/dihapus, tetapi owner tidak dapat dicabut dan hanya diset saat deploy.
- Tidak ada perlindungan reentrancy untuk operasi yang mengirim ETH (lock/withdraw). Fee/liq per perusahaan tidak mempertimbangkan `totalSalary` (field belum pernah di-update).

Testing yang ada
- Test utama di `test/GajiKita.t.sol` dan `test/Proxy.t.sol` (plus stub lama `src/test/GajiKita.t.sol`). Suite meng-cover pendaftaran, alur tarik gaji, fee config, receipt receiver, serta jalur proxy (termasuk inisialisasi dan simulasi upgrade via `vm.store`).
- Perlu diperhatikan: ekspektasi withdraw reward investor/perusahaan dalam test dapat tidak sejalan dengan akuntansi nyata karena reward investor belum dicatat.

Maintenance updates
- Seluruh source utama sudah memakai named imports/aliases sesuai lint Foundry dan modifier yang memiliki logika berat kini dibungkus ke helper internal (`_onlyAdmin`, `_onlyCompany`, `_onlyEmployee`, `_onlyOwner`) untuk mengecilkan bytecode.
- Investor fee kini didistribusikan pro-rata ke `rewardBalance` tiap investor (loop naif), dengan tracking `totalInvestorLiquidity`; penarikan reward investor kini selalu mengosongkan reward balance.
- Beberapa file di `test/` dan artefak lama di `out/` dimiliki root sehingga saat ini tidak bisa saya ubah; ini masih menyisakan lint note unaliased imports di `test/*.t.sol` dan memblok `forge build` default karena `out/GajiKita.sol/GajiKita.json` tak bisa ditulis ulang. Perlu ubah permission/ownership test/ dan out/ agar perubahan lint selesai dan build bisa jalan tanpa sudo.
