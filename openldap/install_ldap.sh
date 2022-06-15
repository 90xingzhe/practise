#!/usr/bin/bash

#关闭防火墙
systemctl stop firewalld

# yum 安装相关包
wget -O /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
yum clean all
yum makecache
yum install -y openldap openldap-clients openldap-servers
 
# 复制一个默认配置到指定目录下,并授权，这一步一定要做，然后再启动服务，不然生产密码时会报错
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
# 授权给ldap用户,此用户yum安装时便会自动创建
chown -R ldap. /var/lib/ldap/DB_CONFIG
 
# 启动服务，先启动服务，配置后面再进行修改
systemctl start slapd
systemctl enable slapd
 
# 查看状态，正常启动则ok
systemctl status slapd


# 生成管理员密码,记录下这个密码，后面需要用到
pwd='123456'
passwd=`slappasswd -s $pwd`

# 新增修改密码文件,ldif为后缀，文件名随意，不要在/etc/openldap/slapd.d/目录下创建类似文件
# 生成的文件为需要通过命令去动态修改ldap现有配置，如下，我在家目录下，创建文件
cat >>changepwd.ldif <<EOF
dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: $passwd
EOF

# 执行命令，修改ldap配置，通过-f执行文件
ldapadd -Y EXTERNAL -H ldapi:/// -f changepwd.ldif

#向LDAP中导入Schema
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/collective.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/corba.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/duaconf.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/dyngroup.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/java.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/misc.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/openldap.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/pmi.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/ppolicy.ldif
 
 
# 修改域名，新增changedomain.ldif, 这里我自定义的域名为 xingzhe.com，管理员用户账号为admin。
# 如果要修改，则修改文件中相应的dc=xingzhe,dc=com为自己的域名
cat >>changedomain.ldif <<EOF
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="cn=admin,dc=xingzhe,dc=com" read by * none


dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=xingzhe,dc=com


dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,dc=xingzhe,dc=com


dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $passwd


dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by dn="cn=admin,dc=xingzhe,dc=com" write by anonymous auth by self write by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by dn="cn=admin,dc=xingzhe,dc=com" write by * read
EOF
 
# 执行命令，修改配置
ldapmodify -Y EXTERNAL -H ldapi:/// -f changedomain.ldif

# 新增add-memberof.ldif, #开启memberof支持并新增用户支持memberof配置
cat >>add-memberof.ldif <<EOF
dn: cn=module{0},cn=config
cn: modulle{0}
objectClass: olcModuleList
objectclass: top
olcModuleload: memberof.la
olcModulePath: /usr/lib64/openldap


dn: olcOverlay={0}memberof,olcDatabase={2}hdb,cn=config
objectClass: olcConfig
objectClass: olcMemberOf
objectClass: olcOverlayConfig
objectClass: top
olcOverlay: memberof
olcMemberOfDangling: ignore
olcMemberOfRefInt: TRUE
olcMemberOfGroupOC: groupOfUniqueNames
olcMemberOfMemberAD: uniqueMember
olcMemberOfMemberOfAD: memberOf
EOF
 
 
# 新增refint1.ldif文件
cat >>refint1.ldif <<EOF
dn: cn=module{0},cn=config
add: olcmoduleload
olcmoduleload: refint
EOF
 
 
# 新增refint2.ldif文件
cat >>refint2.ldif <<EOF
dn: olcOverlay=refint,olcDatabase={2}hdb,cn=config
objectClass: olcConfig
objectClass: olcOverlayConfig
objectClass: olcRefintConfig
objectClass: top
olcOverlay: refint
olcRefintAttribute: memberof uniqueMember  manager owner
EOF
 
# 依次执行下面命令，加载配置，顺序不能错
ldapadd -Q -Y EXTERNAL -H ldapi:/// -f add-memberof.ldif
ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f refint1.ldif
ldapadd -Q -Y EXTERNAL -H ldapi:/// -f refint2.ldif

# 新增配置文件
cat >>base.ldif <<EOF
dn: dc=xingzhe,dc=com
objectClass: top
objectClass: dcObject
objectClass: organization
o: xingzhe Company
dc: xingzhe


dn: cn=admin,dc=xingzhe,dc=com
objectClass: organizationalRole
cn: admin


dn: ou=People,dc=xingzhe,dc=com
objectClass: organizationalUnit
ou: People


dn: ou=Group,dc=xingzhe,dc=com
objectClass: organizationalRole
cn: Group
EOF
 
# 执行命令，添加配置, 这里要注意修改域名为自己配置的域名，然后需要输入上面我们生成的密码
ldapadd -x -D cn=admin,dc=xingzhe,dc=com -w $pwd -f base.ldif


# SSL设置
cat >> certs.ldif <<EOF
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/ldap.crt


dn: cn=config
changetype: modify
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/ldap.key
EOF

ldapmodify -Y EXTERNAL  -H ldapi:/// -f /root/certs.ldif

sed -i 's/\/"/\/ ldaps:\/\/\/"/' /etc/sysconfig/slapd
# 重启ldap服务
systemctl restart slapd

#安装phpldapadmin管理工具
yum localinstall http://rpms.famillecollet.com/enterprise/remi-release-7.rpm -y
yum install -y phpldapadmin

#修改phpldapadmin配置
cp /etc/httpd/conf.d/phpldapadmin.conf /etc/httpd/conf.d/phpldapadmin.conf.bak
sed -i 's/local/all granted/' /etc/httpd/conf.d/phpldapadmin.conf
sed -i '398s/uid/cn/' /etc/phpldapadmin/config.php
sed -i '460s/true/false/' /etc/phpldapadmin/config.php
sed -i '460s/\/\///' /etc/phpldapadmin/config.php
sed -i "519s/r'/r','cn','sn'/p" /etc/phpldapadmin/config.php
sed -i '519s/#//' /etc/phpldapadmin/config.php


mkdir /etc/httpd/ssl

cat >> /etc/httpd/conf.d/default.conf << EOF
<VirtualHost 192.168.3.84:443>
ServerName xingzhe.com
DocumentRoot "/var/www/html/phpldapadmin"
SSLEngine on
SSLProtocol all -SSLv2
SSLCertificateFile /etc/httpd/ssl/httpd.crt
SSLCertificateKeyFile /etc/httpd/ssl/httpd.key
SSLCertificateChainFile /etc/pki/CA/ca.crt
</VirtualHost>
EOF

yum install mod_ssl
# 启动apache
systemctl start httpd
systemctl enable httpd

echo
echo '安装完成'
echo '请访问http://ip/ldapadmin，用户名:admin，密码：123456'
