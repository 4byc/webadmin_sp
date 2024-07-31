import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webadmin_sp/providers/auth_provider.dart'
    as local_auth_provider;

class CommonDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        color: Colors.white,
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
              child: Text(
                'Admin Menu',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.dashboard, color: Colors.cyan),
              title: Text('Dashboard', style: TextStyle(color: Colors.black)),
              onTap: () {
                Navigator.pushReplacementNamed(context, '/dashboard');
              },
            ),
            ListTile(
              leading: Icon(Icons.history, color: Colors.cyan),
              title: Text('History', style: TextStyle(color: Colors.black)),
              onTap: () {
                Navigator.pushReplacementNamed(context, '/history');
              },
            ),
            ListTile(
              leading: Icon(Icons.local_parking, color: Colors.cyan),
              title: Text('Parking Lot', style: TextStyle(color: Colors.black)),
              onTap: () {
                Navigator.pushReplacementNamed(context, '/parking-lot');
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.logout, color: Colors.cyan),
              title: Text('Logout', style: TextStyle(color: Colors.black)),
              onTap: () async {
                final authProvider =
                    Provider.of<local_auth_provider.AuthProvider>(context,
                        listen: false);
                await authProvider.signOut();
                Navigator.pushReplacementNamed(context, '/');
              },
            ),
          ],
        ),
      ),
    );
  }
}
