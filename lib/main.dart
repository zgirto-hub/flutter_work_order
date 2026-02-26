import 'package:flutter/material.dart';
import 'screens/work_order_home.dart';
//?????????????????????????
//!!!!!!!!!!!!!!!

//gjhghjgjhgj
//jkkjhkj
void main() {
  runApp(const WorkOrderApp());
}

class WorkOrderApp extends StatelessWidget {
  const WorkOrderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WorkOrderHome(),
    );
  }
}