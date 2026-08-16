# LeoDigi CyberPanel Toolkit

**Tài liệu:** [Tiếng Việt](README.vi.md) · [English](README.md)

**Sản phẩm được phát triển bởi [LeoDigi](https://leodigi.dev)**

LeoDigi CyberPanel Toolkit là bộ công cụ quản trị mở rộng dành cho **CyberPanel Free + OpenLiteSpeed**. Toolkit hoạt động độc lập, không sửa mã nguồn lõi CyberPanel, nên hạn chế lỗi khi CyberPanel được cập nhật.

> Phiên bản 1.0.2 dành cho quản trị viên có quyền root. Hãy snapshot VPS hoặc thử trên VPS staging trước khi cài lên máy production đang phục vụ website.

## 1. Chức năng

| Module | Chức năng chính |
|---|---|
| Core | Installer, cấu hình, secrets, log, khóa tiến trình, preflight, health check, update, restore point, rollback, uninstall |
| Backup | Restic, Rclone, backup mã hóa, dump MariaDB, retention, integrity check và restore |
| Cloud | Google Drive, Google Shared Drive, OneDrive Personal/Business, SharePoint, S3/MinIO/Wasabi, SFTP và local |
| WordPress | Tìm website, kiểm tra checksum, sửa permission, clone và tạo staging |
| Security | ClamAV, báo cáo file nhiễm, firewall UFW/firewalld và bảo vệ cổng SSH |
| Mail | Postfix/Dovecot diagnostics, mail queue, Rspamd và Redis tùy chọn |
| SSL | acme.sh, SSL thường, wildcard SSL qua DNS API và kiểm tra thời hạn |
| Monitoring | CPU, RAM, disk, inode, dịch vụ, Netdata tùy chọn, Telegram/email alert |
| Dashboard | Dashboard nội bộ có đăng nhập, chỉ chạy các tác vụ kiểm tra an toàn |

## 2. Hệ điều hành hỗ trợ

- Ubuntu 22.04 hoặc 24.04.
- AlmaLinux 8 hoặc 9.
- Rocky Linux 8 hoặc 9.
- CyberPanel đã được cài tại `/usr/local/CyberCP`.
- OpenLiteSpeed tại `/usr/local/lsws`.
- VPS dùng systemd và có quyền `root`/`sudo`.

Không cài lên CentOS 7, VPS không có systemd hoặc máy chưa cài CyberPanel.

## 3. Chuẩn bị trước khi cài

### Bước 1: Đăng nhập VPS

```bash
ssh root@IP_VPS
```

### Bước 2: Kiểm tra hệ điều hành và dung lượng

```bash
cat /etc/os-release
df -h /
free -h
```

Nên còn ít nhất 2 GB ổ đĩa. Nếu VPS đang chạy production, hãy tạo snapshot từ nhà cung cấp VPS trước.

### Bước 3: Kiểm tra CyberPanel/OpenLiteSpeed

```bash
test -d /usr/local/CyberCP && echo "CyberPanel: OK"
test -d /usr/local/lsws && echo "OpenLiteSpeed: OK"
systemctl status lscpd --no-pager
systemctl status lsws --no-pager
```

## 4. Tải source từ GitHub

Repository đang private. Hãy dùng Deploy Key hoặc đăng nhập GitHub; không đặt token trực tiếp trong lệnh để tránh lưu vào shell history.

```bash
cd /root
git clone https://github.com/leodigi92/leodigi-cyberpanel-toolkit.git
cd leodigi-cyberpanel-toolkit
```

Nếu tải file ZIP:

```bash
unzip leodigi-cyberpanel-toolkit-v1.0.2.zip
cd leodigi-cyberpanel-toolkit
```

## 5. Kiểm tra source trước khi cài

```bash
bash tests/run.sh
```

Kết quả đúng:

```text
1.0.2
All tests passed
```

## 6. Chạy preflight không thay đổi VPS

Installer mặc định chỉ kiểm tra, không cài ngay:

```bash
sudo bash install.sh --profile full
```

Nếu thấy cảnh báo thiếu CyberPanel, OpenLiteSpeed hoặc thiếu dung lượng, hãy xử lý trước. Không thêm `--apply` khi preflight chưa đạt.

## 7. Chọn profile

### Minimal

Chỉ cài Core và lệnh `toolkitctl`:

```bash
sudo bash install.sh --profile minimal --apply
```

### Standard

Cài Core, Backup, WordPress, Security, SSL và Monitoring:

```bash
sudo bash install.sh --profile standard --apply
```

### Full

Cài toàn bộ module và Dashboard:

```bash
sudo bash install.sh --profile full --apply
```

Nếu muốn chạy không hỏi lại:

```bash
sudo bash install.sh --profile full --apply --yes
```

Không dùng `--yes` ở lần cài đầu trên VPS production.

## 8. Kiểm tra ngay sau khi cài

```bash
sudo toolkitctl version
sudo toolkitctl preflight
sudo toolkitctl health
sudo toolkitctl doctor
sudo toolkitctl module list
systemctl list-timers 'leodigi-cpt-*'
```

Thư mục sau khi cài:

```text
/opt/leodigi-cyberpanel-toolkit              Mã chương trình
/etc/leodigi-cyberpanel-toolkit              Cấu hình
/etc/leodigi-cyberpanel-toolkit/secrets      Token và mật khẩu
/var/lib/leodigi-cyberpanel-toolkit          Trạng thái, báo cáo
/var/log/leodigi-cyberpanel-toolkit          Log
/var/backups/leodigi-cyberpanel-toolkit      Bản sao cấu hình an toàn
```

## 9. Cấu hình Backup

### Bước 1: Cài module

```bash
sudo toolkitctl module install backup --apply --yes
```

### Bước 2: Tạo kết nối cloud

```bash
sudo toolkitctl backup remote add
```

Trong Rclone chọn:

- `drive`: Google Drive hoặc Shared Drive.
- `onedrive`: OneDrive Personal, OneDrive Business hoặc SharePoint.
- `s3`: S3, MinIO, Wasabi.
- `sftp`: VPS/NAS khác qua SSH.

VPS không có trình duyệt sẽ yêu cầu xác thực trên máy tính cá nhân. Không gửi token OAuth qua chat hoặc commit lên GitHub.

### Google Drive

Từ năm 2026, Client ID dùng chung của Rclone đang được ngừng hỗ trợ. Hãy tạo OAuth Client ID riêng để backup không bị gián đoạn.

#### 1. Tạo OAuth Client riêng

1. Mở [Google Cloud Console](https://console.cloud.google.com/) và tạo/chọn một project, ví dụ `LeoDigi CyberPanel Backup`.
2. Vào **APIs & Services > Library**, tìm **Google Drive API** rồi nhấn **Enable**.
3. Vào **Google Auth Platform > Branding** và cấu hình màn hình đồng ý OAuth.
4. Nếu dùng tài khoản Google cá nhân, chọn **External**. Trong thời gian ứng dụng ở chế độ Testing, vào **Audience > Test users** và thêm chính tài khoản Google Drive nhận backup.
5. Vào **Google Auth Platform > Clients > Create Client**.
6. Chọn **Application type: Desktop app**, đặt tên `LeoDigi Rclone`, rồi tạo Client.
7. Lưu lại **Client ID** và **Client Secret**. Không gửi các giá trị này qua chat, không chụp màn hình và không commit lên GitHub.

Client ID đầy đủ thường kết thúc bằng `.apps.googleusercontent.com`. Nếu Client Secret đã bị lộ, hãy xóa OAuth Client cũ và tạo Client mới.

#### 2. Tạo remote trên VPS

```bash
sudo toolkitctl backup remote add
```

Trong trình cấu hình Rclone:

```text
New remote name> gdrive-main
Storage> drive
client_id> CLIENT_ID_CUA_BAN
client_secret> CLIENT_SECRET_CUA_BAN
scope> 1
service_account_file> [nhấn Enter để trống]
Edit advanced config? n
Use web browser to automatically authenticate rclone with remote? n
```

Số thứ tự của `drive` có thể thay đổi theo phiên bản Rclone; hãy chọn mục có tên **Google Drive** thay vì phụ thuộc cố định vào một con số.

Sau khi chọn `n` ở bước mở trình duyệt, giữ nguyên cửa sổ SSH. VPS sẽ hiển thị lệnh gần giống:

```bash
rclone authorize "drive" "CHUOI_CAU_HINH"
```

và chờ tại `config_token>`.

#### 3. Xác thực trên máy Windows không cần trình duyệt trên VPS

Tải bản Rclone mới từ [rclone.org/downloads](https://rclone.org/downloads/) và giải nén, ví dụ tại `D:\Rclone`. Mở CMD rồi chạy **nguyên lệnh VPS cung cấp**, chỉ thay chương trình `rclone` bằng đường dẫn:

```cmd
D:\Rclone\rclone.exe authorize "drive" "CHUOI_CAU_HINH"
```

Phải dùng `"drive"`, không dùng `"onedrive"`. Trình duyệt trên Windows sẽ mở để đăng nhập Google và cấp quyền. Copy toàn bộ token JSON mà CMD trả về, dán vào `config_token>` trên VPS rồi nhấn Enter. Không gửi hoặc lưu token này trong tài liệu công khai.

Nếu Rclone hỏi **Configure this as a Shared Drive?**:

- Chọn `n` nếu lưu trong **My Drive/Google Drive cá nhân**.
- Chọn `y` nếu dùng **Google Workspace Shared Drive**, sau đó chọn đúng Shared Drive.

Tại **Keep this remote?**, chọn `y`; sau đó chọn `q` để thoát cấu hình.

#### 4. Kiểm tra kết nối

```bash
sudo toolkitctl backup remote list
sudo toolkitctl backup remote test gdrive-main
```

Kết nối thành công khi lệnh test liệt kê được thư mục trên Drive và không báo lỗi OAuth/API. Có thể tạo một thư mục thử:

```bash
sudo env RCLONE_CONFIG=/etc/leodigi-cyberpanel-toolkit/secrets/rclone.conf \
  rclone mkdir gdrive-main:LeoDigi-Backups/Test
sudo env RCLONE_CONFIG=/etc/leodigi-cyberpanel-toolkit/secrets/rclone.conf \
  rclone lsd gdrive-main:LeoDigi-Backups
```

File cấu hình có token được lưu tại `/etc/leodigi-cyberpanel-toolkit/secrets/rclone.conf`. Giữ quyền truy cập file ở mức `600` và chỉ cho root:

```bash
sudo chown root:root /etc/leodigi-cyberpanel-toolkit/secrets/rclone.conf
sudo chmod 600 /etc/leodigi-cyberpanel-toolkit/secrets/rclone.conf
```

Sau khi tạo remote, tiếp tục tạo profile Restic ở Bước 3 bên dưới. Không bật lịch backup tự động cho đến khi chạy backup và restore thử thành công.

### OneDrive/Microsoft 365

Đối với OneDrive Business, khai báo Tenant ID và ứng dụng Microsoft Entra. Với SharePoint, ưu tiên quyền `Sites.Selected` và chỉ cấp quyền đúng site lưu backup.

```bash
sudo toolkitctl backup remote test onedrive-company
sudo toolkitctl backup remote test sharepoint-backup
```

### Bước 3: Tạo profile Restic

```bash
sudo toolkitctl backup configure
```

Ví dụ nhập:

```text
Profile name: production
Rclone remote: gdrive-main
Repository path: CyberPanel-Backups/vps-01
```

Mật khẩu Restic được tạo tại:

```text
/etc/leodigi-cyberpanel-toolkit/secrets/restic-production.password
```

Hãy lưu một bản mật khẩu này ở nơi an toàn khác. Mất mật khẩu đồng nghĩa không thể giải mã backup.

### Bước 4: Chạy backup đầu tiên

```bash
sudo toolkitctl backup run production
sudo toolkitctl backup list production
sudo toolkitctl backup check production
```

### Bước 5: Kiểm tra lịch tự động

```bash
systemctl status leodigi-cpt-backup.timer --no-pager
systemctl list-timers leodigi-cpt-backup.timer
```

### Restore an toàn

Không restore thẳng vào `/` hoặc document root đang chạy. Luôn restore sang thư mục mới:

```bash
sudo mkdir -p /restore/cyberpanel-test
sudo toolkitctl backup restore production SNAPSHOT_ID /restore/cyberpanel-test
```

Sau đó kiểm tra file, quét malware và import database thủ công. Toolkit không tự ghi đè database production.

## 10. WordPress clone và staging

Trước tiên tạo website đích và database đích trong CyberPanel.

```bash
sudo toolkitctl wp list
sudo toolkitctl wp health example.com
sudo toolkitctl wp permissions example.com --apply
```

Clone sang website đã tạo:

```bash
sudo toolkitctl wp clone example.com staging.example.com
```

Hoặc:

```bash
sudo toolkitctl wp staging example.com staging.example.com
```

Toolkit sẽ backup trước, sao chép file bằng rsync, dump/import database, chạy search-replace URL và tắt index cho staging.

## 11. Quét malware

```bash
sudo toolkitctl module install security --apply --yes
sudo toolkitctl malware scan example.com
sudo toolkitctl malware scan-all
sudo toolkitctl malware report
```

Mặc định toolkit chỉ báo cáo, không tự xóa file. Khi phát hiện mã độc:

1. Đưa website vào maintenance.
2. Lưu backup hiện trạng để điều tra.
3. Kiểm tra report.
4. Khôi phục file sạch từ snapshot.
5. Đổi mật khẩu quản trị, database, FTP/SSH.
6. Cập nhật WordPress, plugin và theme.

## 12. Firewall

Firewall bị vô hiệu hóa mặc định để tránh tự khóa SSH. Mở file:

```bash
sudo nano /etc/leodigi-cyberpanel-toolkit/toolkit.env
```

Đặt đúng cổng SSH:

```text
FIREWALL_MANAGE=yes
FIREWALL_SSH_PORT=22
```

Giữ một cửa sổ SSH thứ hai đang mở rồi chạy:

```bash
sudo toolkitctl firewall status
sudo toolkitctl firewall apply --apply
sudo toolkitctl firewall status
```

### Mở cổng trên giao diện CyberPanel

Đăng nhập CyberPanel bằng tài khoản quản trị, mở **Security > Firewall** hoặc **Firewall Management**. Trong phần **Firewall Rules**, điền:

| Trường | Giá trị ví dụ | Giải thích |
|---|---|---|
| Rule Name | `toolkit-dashboard` | Tên dễ nhận biết |
| Protocol | `TCP` | Dashboard và dịch vụ web dùng TCP |
| IP Address | `IP_QUAN_TRI/32` | Khuyến nghị chỉ cho phép IP công cộng của quản trị viên |
| Port | `9443` | Cổng Dashboard mặc định |

Nhấn **Add Rule**, sau đó **Reload** firewall nếu giao diện yêu cầu. Không dùng `0.0.0.0/0` trừ khi thật sự muốn cho toàn Internet truy cập cổng đó.

Ví dụ chỉ cho IP `203.0.113.10` truy cập:

```text
Rule Name: toolkit-dashboard
Protocol: TCP
IP Address: 203.0.113.10/32
Port: 9443
```

Nếu nhà cung cấp VPS có **Cloud Firewall**, **Security Group** hoặc **Network ACL**, cần tạo rule TCP tương tự ở trang quản trị của nhà cung cấp. Firewall trong CyberPanel không thể vượt qua rule đang chặn ở lớp cloud.

### Mở cổng qua SSH

Kiểm tra cổng SSH thực tế trước khi bật firewall và luôn giữ một phiên SSH thứ hai đang mở:

```bash
sudo ss -lntp | grep -E ':(22|9443)\b'
sudo toolkitctl firewall status
```

Mở cổng bằng Toolkit:

```bash
sudo toolkitctl firewall open 9443/tcp --apply
sudo toolkitctl firewall status
```

Lệnh trên có thể cho phép mọi nguồn tùy backend firewall. Với Ubuntu/UFW, an toàn hơn là chỉ cho IP quản trị:

```bash
sudo ufw allow from IP_QUAN_TRI to any port 9443 proto tcp comment 'LeoDigi Toolkit Dashboard'
sudo ufw status numbered
```

Với firewalld, tạo rich rule giới hạn IP:

```bash
sudo firewall-cmd --permanent \
  --add-rich-rule='rule family="ipv4" source address="IP_QUAN_TRI/32" port protocol="tcp" port="9443" accept'
sudo firewall-cmd --reload
sudo firewall-cmd --list-all
```

Đóng cổng đã mở bằng Toolkit:

```bash
sudo toolkitctl firewall close 9443/tcp --apply
```

Nếu đã tạo rule UFW giới hạn IP, xóa đúng rule bằng:

```bash
sudo ufw status numbered
sudo ufw delete SO_THU_TU_RULE
```

### Kiểm tra sau khi mở cổng

```bash
sudo ss -lntp | grep ':9443'
sudo systemctl status leodigi-cpt-dashboard --no-pager
curl -I http://127.0.0.1:9443/
```

Từ máy quản trị có thể kiểm tra bằng PowerShell:

```powershell
Test-NetConnection IP_VPS -Port 9443
```

Google Drive/Rclone **không yêu cầu mở cổng inbound**. Backup cloud chỉ cần kết nối outbound HTTPS TCP 443, mặc định firewall cho phép. Cổng `9443` chỉ liên quan đến Dashboard.

Không mở cổng `7080` hoặc Dashboard công khai nếu không giới hạn IP.

## 13. Mail và Rspamd

Kiểm tra hệ thống mail hiện tại:

```bash
sudo toolkitctl mail status
sudo toolkitctl mail queue
sudo toolkitctl mail check mail.example.com
```

Cài Rspamd/Redis:

```bash
sudo toolkitctl mail install-rspamd --apply
```

Kiểm tra lại:

```bash
sudo rspamadm configtest
sudo postfix check
sudo systemctl status rspamd redis postfix --no-pager
```

Ngưỡng mặc định ban đầu:

```text
greylist: 4
add header: 6
reject: 15
```

Hãy theo dõi false positive trước khi giảm ngưỡng reject.

## 14. Wildcard SSL qua DNS API

Cài module:

```bash
sudo toolkitctl module install ssl --apply --yes
```

Tạo file secrets:

```bash
sudo install -m 600 /dev/null /etc/leodigi-cyberpanel-toolkit/secrets/dns-api.env
sudo nano /etc/leodigi-cyberpanel-toolkit/secrets/dns-api.env
```

Ví dụ Cloudflare dùng token có quyền DNS tối thiểu theo hướng dẫn acme.sh. Sau đó:

```bash
sudo toolkitctl ssl wildcard example.com dns_cf
sudo toolkitctl ssl renew
sudo toolkitctl ssl check example.com
```

Không commit `dns-api.env` lên GitHub.

## 15. Monitoring và cảnh báo

Kiểm tra nhanh:

```bash
sudo toolkitctl monitoring status
sudo toolkitctl health
sudo toolkitctl doctor
```

Muốn cài Netdata, sửa:

```text
NETDATA_INSTALL=yes
```

Rồi chạy:

```bash
sudo toolkitctl module install monitoring --apply --yes
```

Telegram token phải để trong file secrets hoặc môi trường local, không đưa lên GitHub. Kiểm tra cảnh báo:

```bash
sudo toolkitctl monitoring test-alert
```

## 16. Dashboard

Cài và tạo mật khẩu:

```bash
sudo toolkitctl module install dashboard --apply --yes
sudo toolkitctl dashboard reset-password
sudo toolkitctl dashboard status
```

Dashboard mặc định chỉ nghe tại:

```text
127.0.0.1:9443
```

Với cấu hình này, không cần mở cổng `9443` để dùng reverse proxy. Hãy tạo subdomain HTTPS trong OpenLiteSpeed rồi reverse proxy tới `127.0.0.1:9443`, kết hợp giới hạn IP hoặc VPN.

Nếu cần truy cập trực tiếp qua cổng `9443` trong mạng riêng/VPN, sửa:

```bash
sudo nano /etc/leodigi-cyberpanel-toolkit/toolkit.env
```

Đặt:

```text
DASHBOARD_BIND=0.0.0.0
DASHBOARD_PORT=9443
```

Sau đó:

```bash
sudo systemctl restart leodigi-cpt-dashboard
sudo ss -lntp | grep ':9443'
```

Tiếp theo mở firewall theo hướng dẫn ở mục 12 và chỉ cho phép IP quản trị hoặc dải mạng VPN. Truy cập trực tiếp `http://IP_VPS:9443` không có TLS ở lớp Uvicorn; không nên dùng qua Internet công cộng vì thông tin đăng nhập có thể đi qua kết nối không mã hóa. Phương án production được khuyến nghị là subdomain HTTPS reverse proxy.

Dashboard chỉ cung cấp hành động đọc/kiểm tra. Những thao tác xóa, restore, firewall hoặc clone website vẫn phải dùng CLI và xác nhận.

## 17. Log và xử lý lỗi

Xem log gần nhất:

```bash
sudo toolkitctl logs
```

Xem service:

```bash
journalctl -u leodigi-cpt-backup.service -n 100 --no-pager
journalctl -u leodigi-cpt-health.service -n 100 --no-pager
journalctl -u leodigi-cpt-dashboard.service -n 100 --no-pager
```

## 18. Rollback

Liệt kê restore point:

```bash
sudo toolkitctl restore-points
```

Khôi phục một restore point:

```bash
sudo toolkitctl rollback RESTORE_POINT_ID
```

Sau rollback, kiểm tra cú pháp và restart đúng dịch vụ liên quan.

## 19. Update

Update yêu cầu package `.tar.gz` và file `.sha256` tương ứng:

```bash
sudo toolkitctl update /root/cyberpanel-toolkit-1.1.0.tar.gz
```

Toolkit kiểm tra checksum, backup phiên bản cũ, cài phiên bản mới rồi chạy health check.

## 20. Gỡ cài đặt

Gỡ chương trình nhưng giữ cấu hình và dữ liệu:

```bash
sudo toolkitctl uninstall
```

Chỉ dùng tùy chọn sau khi chắc chắn không cần cấu hình local:

```bash
sudo toolkitctl uninstall --purge-data
```

Uninstall không xóa website, database hoặc repository Restic trên cloud.

## 21. Checklist nghiệm thu

```bash
sudo toolkitctl version
sudo toolkitctl preflight
sudo toolkitctl health
sudo toolkitctl doctor
sudo toolkitctl backup run production
sudo toolkitctl backup check production
sudo toolkitctl wp health example.com
sudo toolkitctl mail check mail.example.com
sudo toolkitctl ssl check example.com
sudo toolkitctl monitoring test-alert
```

Chỉ xem là backup hoạt động khi đã restore thử thành công vào thư mục riêng.

## 22. Lưu ý quan trọng

- Google Drive, OneDrive và SharePoint có thể giới hạn API khi backup lớn; nên dùng S3/MinIO làm repository chính cho nhiều VPS.
- Không lưu cùng một bản backup duy nhất trên chính VPS nguồn.
- Không tự động xóa file malware trước khi xác định nguyên nhân.
- Không bật firewall nếu chưa xác nhận cổng SSH.
- Không mở Dashboard, Netdata hoặc OpenLiteSpeed Admin trực tiếp ra Internet.
- Luôn cập nhật CyberPanel, hệ điều hành, WordPress, plugin và theme.

## License

MIT. Xem [LICENSE](LICENSE).

Website chính thức: [leodigi.dev](https://leodigi.dev)
