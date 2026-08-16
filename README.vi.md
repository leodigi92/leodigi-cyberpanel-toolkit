# LeoDigi CyberPanel Toolkit

**Tài liệu:** [Tiếng Việt](README.vi.md) · [English](README.md)

LeoDigi CyberPanel Toolkit là bộ công cụ quản trị mở rộng dành cho **CyberPanel Free + OpenLiteSpeed**. Toolkit hoạt động độc lập, không sửa mã nguồn lõi CyberPanel, nên hạn chế lỗi khi CyberPanel được cập nhật.

> Phiên bản 1.0.1 dành cho quản trị viên có quyền root. Hãy snapshot VPS hoặc thử trên VPS staging trước khi cài lên máy production đang phục vụ website.

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
unzip leodigi-cyberpanel-toolkit-v1.0.1.zip
cd leodigi-cyberpanel-toolkit
```

## 5. Kiểm tra source trước khi cài

```bash
bash tests/run.sh
```

Kết quả đúng:

```text
1.0.1
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

Nên tạo OAuth Client ID riêng trong Google Cloud thay vì Client ID dùng chung. Sau khi tạo remote, kiểm tra:

```bash
sudo toolkitctl backup remote list
sudo toolkitctl backup remote test gdrive-main
```

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

Mở/đóng cổng riêng:

```bash
sudo toolkitctl firewall open 9443/tcp --apply
sudo toolkitctl firewall close 9443/tcp --apply
```

Không mở cổng 7080 hoặc Dashboard công khai nếu không giới hạn IP.

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

Không truy cập trực tiếp từ Internet. Hãy tạo subdomain HTTPS trong OpenLiteSpeed rồi reverse proxy tới `127.0.0.1:9443`, kết hợp giới hạn IP hoặc VPN.

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
