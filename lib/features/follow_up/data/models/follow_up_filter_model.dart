import 'package:gps_cielo/features/follow_up/presentation/controllers/follow_up_controller.dart';

class FollowUpFilterModel {
  final FollowUpTab selectedTab;
  final String searchQuery;
  final int totalCount;

  FollowUpFilterModel({
    required this.selectedTab,
    required this.searchQuery,
    required this.totalCount,
  });
}
